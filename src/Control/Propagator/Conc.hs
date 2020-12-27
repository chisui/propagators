{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE NoImplicitPrelude    #-}
{-# LANGUAGE StrictData           #-}
module Control.Propagator.Conc where

import "base" Prelude hiding ( (.), id )
import "base" GHC.Generics ( Generic )
import "base" Data.Function ( on )
import "base" Data.Unique
import "base" Data.IORef
import "base" Data.Typeable
import "base" Data.Type.Equality
import "base" Unsafe.Coerce
import "base" Control.Applicative
import "base" Control.Monad
import "base" Control.Concurrent
import "base" Control.Monad.IO.Class
import "base" Control.Category

import "containers" Data.Set ( Set )
import "containers" Data.Set qualified as Set

import "transformers" Control.Monad.Trans.Reader ( ReaderT(..) )

import "mtl" Control.Monad.Reader.Class

import "this" Data.ShowM
import "this" Control.Propagator.Class
import "this" Data.Lattice
import "this" Data.MutList ( MutList )
import "this" Data.MutList qualified as MutList

-------------------------------------------------------------------------------
-- CellVal
-------------------------------------------------------------------------------

data CellVal a = CellVal
    { cellId     :: Cell Par a
    , getCellVal :: IORef a
    , listeners  :: IORef (Set (Listener a))
    }

newCellVal :: Cell Par a -> a -> IO (CellVal a)
newCellVal idA a = CellVal idA
                <$> newIORef a
                <*> newIORef Set.empty

copyCellVal :: Value a => CellVal a -> IO (CellVal a)
copyCellVal cv = CellVal (cellId cv)
              <$> copyIORef (getCellVal cv)
              <*> copyIORef (listeners cv)

copyIORef :: IORef a -> IO (IORef a)
copyIORef r = newIORef =<< readIORef r

instance Show a => Show (CellVal a) where
    showsPrec d = showsPrec d . cellId

instance Show a => ShowM IO (CellVal a) where
    showsPrecM d cv = do
        let idA = cellId cv
        a <- readIORef . getCellVal $ cv
        ls <- readIORef . listeners $ cv
        pure . showParen (d >= 10)
            $ shows idA
            . showString " = " . showsPrec 0 a
            . showString " listeners=" . (shows . Set.toList $ ls)

instance Eq a => Eq (CellVal a) where
    a == b = on (==) cellId a b && on (==) getCellVal a b

instance Ord a => Ord (CellVal a) where
    compare = compare `on` cellId

data AnyCellVal where
    AnyCellVal :: Value a => CellVal a -> AnyCellVal

toCellVal :: (Value a, MonadFail m) => AnyCellVal -> m (CellVal a)
toCellVal (AnyCellVal ref) = castM ref

copyAnyCellVal :: AnyCellVal -> IO AnyCellVal
copyAnyCellVal (AnyCellVal v) = AnyCellVal <$> copyCellVal v

castM :: (Typeable a, Typeable b, MonadFail m) => a -> m b
castM a = do
    let Just b = cast a
    pure b

-------------------------------------------------------------------------------
-- Listener
-------------------------------------------------------------------------------

data Listener a = Listener
    { listenerId     :: Unique
    , listenerDirty  :: IORef Bool
    , listenerAction :: a -> Par ()
    }

newListener :: (a -> Par ()) -> IO (Listener a)
newListener l = Listener
    <$> newUnique
    <*> newIORef False
    <*> pure l

instance Eq (Listener a) where
    a == b = compare a b == EQ
instance Ord (Listener a) where
    compare = compare `on` listenerId

instance Show (Listener a) where
    showsPrec d (Listener lId _ _) = showParen (d >= 10) $ showString "Listener " . shows (hashUnique lId)

-------------------------------------------------------------------------------
-- ParState
-------------------------------------------------------------------------------

data ParState = ParState
    { jobCount :: IORef Int
    , cells    :: MutList AnyCellVal
    }

newParState :: IO ParState
newParState = ParState <$> newIORef 0 <*> MutList.new

newCellIO :: forall a. Value a => String -> a -> ParState -> IO (Cell Par a)
newCellIO name a s = do
    i <- MutList.add undefined . cells $ s
    let idA = PID name i
    cv <- newCellVal idA a
    MutList.write i (AnyCellVal cv) . cells $ s
    pure idA

readCellVal :: Value a => Cell Par a -> Par (CellVal a)
readCellVal idA = MkPar $ toCellVal =<< liftIO . MutList.read (cellIndex idA) =<< cells <$> ask

copyParState :: ParState -> IO ParState
copyParState s = ParState
             <$> newIORef 0
             <*> (MutList.map copyAnyCellVal . cells $ s)

-------------------------------------------------------------------------------
-- Par
-------------------------------------------------------------------------------

newtype Par a = MkPar
    { runPar' :: ReaderT ParState IO a
    }
  deriving newtype (Functor, Applicative, Alternative, Monad, MonadIO)

execPar :: Par a -> (a -> Par b) -> IO b
execPar = execPar' 100000 -- 100 millsec

execPar' :: Int -> Par a -> (a -> Par b) -> IO b
execPar' tick setup doneP = do
    s <- newParState
    a <- runPar s setup
    waitForDone s
    runPar s . doneP $ a
  where
    waitForDone s = do
        threadDelay tick
        jobs <- readIORef . jobCount $ s
        unless (jobs == 0) . waitForDone $ s

runPar :: ParState -> Par a -> IO a
runPar s = flip runReaderT s . runPar'

-- Cell

instance Show (Cell Par a) where
    show (PID n i) = n ++ '@' : show i

instance TestEquality (Cell Par) where
    testEquality a b 
        = if cellIndex a == cellIndex b
          then unsafeCoerce $ Just Refl
          else Nothing

-- Sub

instance Eq (Subscription Par) where
    Sub cA lA == Sub cB lB = case testEquality cA cB of
        Just Refl -> cA == cB && lA == lB
        Nothing   -> False

instance Show (Subscription Par) where
    showsPrec d (Sub c l)
        = showParen (d >= 10)
        $ showString "Sub "
        . showsPrec 10 c
        . showString " "
        . showsPrec 10 l

-- PropagatorMonad

instance PropagatorMonad Par where

    data Cell Par a = PID
        { cellName  :: String
        , cellIndex :: Int
        }
      deriving (Eq, Ord, Generic)

    data Subscription Par where
        Sub :: Value a => Cell Par a -> Listener a -> Subscription Par

    newCell n a = MkPar $ liftIO . newCellIO n a =<< ask

    readCell = (liftIO . readIORef . getCellVal =<<) . readCellVal

    write c a = do
        cv <- readCellVal c
        changed <- liftIO $ atomicModifyIORef' (getCellVal cv) (meetEq a)
        when changed $ do
            ls <- fmap Set.toList . liftIO . readIORef . listeners $ cv
            mapM_ (forkListener c) ls
    
    watch c l = do
        l' <- liftIO . newListener $ l
        ls <- fmap listeners . readCellVal $ c
        liftIO . atomicModifyIORef' ls $ (,()) . Set.insert l'
        forkListener c l'
        pure . Subscriptions . pure $ Sub c l'
    
    cancel = mapM_ cancel' . getSubscriptions
      where
        cancel' (Sub c l) = do
            liftIO $ writeIORef (listenerDirty l) False
            ls <- fmap listeners . readCellVal $ c
            liftIO . atomicModifyIORef' ls $ (,()) . Set.delete l

forkListener :: Value a => Cell Par a -> Listener a -> Par ()
forkListener c (Listener _ dirty l) = do
    done <- startJob
    liftIO $ writeIORef dirty True
    void . MkPar . ReaderT $ \ s -> forkIO $ do
        d <- atomicModifyIORef' dirty (False,)
        when d $ do
            runPar s $ l =<< readCell c
        done
            
instance Forkable Par where
    fork m = do
        done <- startJob
        void . MkPar . ReaderT $ \ s -> do
            s' <- liftIO $ copyParState s
            liftIO $ connectStates s s'
            forkIO $ do
                runPar s' $ m (liftParent s)
                done

liftParent :: ParState -> LiftParent Par
liftParent s = liftIO . runPar s

connectStates :: ParState -> ParState -> IO ()
connectStates _ _ = undefined

startJob :: Par (IO ())
startJob = do
    jobs <- jobCount <$> MkPar ask
    liftIO . atomicModifyIORef' jobs $ (,()) . succ
    pure $ atomicModifyIORef' jobs $ (,()) . pred
