{-# LANGUAGE NoImplicitPrelude #-}
module Control.Propagator.Simple
    ( SimplePropagator(..)
    , runSimplePropagator
    , (=~~=)
    ) where

import "base" Prelude hiding ( (.), id )
import "base" Data.Bifunctor
import "base" Data.Typeable
import "base" Control.Category
import "base" Control.Applicative
import "base" Control.Monad.Fix
import "base" Control.Monad

import "transformers" Control.Monad.Trans.State.Strict ( State, evalState )
import "transformers" Control.Monad.Trans.Except
import "mtl" Control.Monad.State.Class ( MonadState, {-state,-} gets , get, put)

import "this" Data.Lattice
import "this" Data.Var
import "this" Data.Iso

import "this" Control.Propagator.Class
import "this" Control.Propagator.CellVal

type SPState = (PoolF (CellVal SimplePropagator), [SimplePropagator ()])
newtype SimplePropagator a = MkSP
    { runSP :: ExceptT String (State SPState) a
    }
  deriving newtype
    ( Functor, Applicative, Monad
    , MonadState SPState
    , MonadFix
    , Alternative, MonadPlus
    )
instance MonadFail SimplePropagator where
    fail = MkSP . throwE

--TODO: do the queue switching here somewhere!
runSimplePropagator :: SimplePropagator a -> Either String a
runSimplePropagator = flip evalState (poolF,[]) . runExceptT . runSP . queuePropagation

queuePropagation :: SimplePropagator a -> SimplePropagator a
queuePropagation p = do
  res <- p
  (s,q) <- get
  put (s, []) --clear the queue for new listeners
  if null q
    then return res
    --TODO: does this do what it should? The output of the action kinda depends on the state. If that one is not changed accordingly, the monad should be reevaluated...nope, tried it. Does not do what it should.
    else sequence q >> return res

instance Show (Cell SimplePropagator a) where
    showsPrec _ c
        = showString (cellName c)
        . shows (unSPC c)

toPool::SPState -> PoolF (CellVal SimplePropagator)
toPool = fst

poolAct :: (PoolF (CellVal SimplePropagator) -> (a, PoolF (CellVal SimplePropagator))) -> SimplePropagator a
poolAct act = do
  (p,s) <- get
  (out, p') <- return $ act p
  put (p',s)
  return out

queueAct :: ([SimplePropagator ()] -> (a, [SimplePropagator ()])) -> SimplePropagator a
queueAct act = do
  (p,s) <- get
  (out, s') <- return $ act s
  put (p,s')
  return out

addToQueue :: [SimplePropagator ()] -> SimplePropagator ()
addToQueue lst = queueAct $ ((),).((++) lst)

(=~~=) :: Cell SimplePropagator a -> Cell SimplePropagator b -> Maybe (a :~: b)
MkSPC _ a =~~= MkSPC _ b = a =~= b

getVal' :: Cell SimplePropagator a -> SimplePropagator (CellVal SimplePropagator a)
getVal' c = gets $ (getVarF $ unSPC c) . toPool

setVal' :: Cell SimplePropagator a -> CellVal SimplePropagator a -> SimplePropagator ()
setVal' (MkSPC _ i) v = poolAct $ ((),) . setVarF i v

callListeners :: (Ord a, Meet a) => Cell SimplePropagator a -> SimplePropagator ()
callListeners c = getVal' c >>= callListeners'

callListeners' :: (Ord a, Meet a) => CellVal SimplePropagator a -> SimplePropagator ()
callListeners' (Ref c _) = callListeners c
callListeners' (Val a ls ms) = do
    execListeners a ls
    mapM_ (callMapping a) ms
  where
    --TODO: make listeners check for change!
    execListeners newVal = (\v -> addToQueue $ ($ newVal) <$> v) . vars
    callMapping newVal (Mapping _ i mls) = execListeners (from i newVal) mls

instance PropagatorMonad SimplePropagator where
    data Cell SimplePropagator a = MkSPC
        { cellName :: String
        , unSPC :: IdF (PoolF (CellVal SimplePropagator)) (CellVal SimplePropagator) a
        }
      deriving (Eq, Ord)

    newtype Subscription SimplePropagator = SPSubs
        { unsSPSubs :: [Sub SimplePropagator]
        }
      deriving newtype (Eq, Ord, Show, Semigroup, Monoid)

    newCell n a = poolAct $ first (MkSPC n) . newVarF (Val a pool [])
    readCell = (readCell' =<<) . getVal'
      where
        readCell' (Val v _ _) = pure v
        readCell' (Ref c i)   = to i <$> readCell c

    write c setVal = getVal' c >>= write'
      where
        write' (Val oldVal ls ms) = do
            let newVal = oldVal /\ setVal
            if oldVal /= newVal
            then do
                setVal' c $ Val newVal ls ms
                callListeners c
            else pure ()
        write' (Ref c' i) = write c' . from i $ setVal

    watch c w = getVal' c >>= watch'
      where
        watch' (Val a v m) = do
            let (i, v') = newVar w v
            setVal' c $ Val a v' m
            --callListeners c
            addToQueue [w a]
            pure . SPSubs . pure $ Sub c i
        watch' (Ref c' m) = watch c' $ w . to m

    cancel = mapM_ cancel' . unsSPSubs
      where
        cancel' (Sub c l) = getVal' c >>= cancelCell
          where
            cancelCell (Val a lx m) = setVal' c $ Val a (delVar l lx) m
            cancelCell (Ref refC _) = getVal' refC >>= cancelRef refC

            cancelRef :: Cell SimplePropagator a -> CellVal SimplePropagator a -> SimplePropagator ()
            cancelRef _ (Ref refC _) = getVal' refC >>= cancelRef refC
            -- ^ should not happen, since references should only point to Vals
            cancelRef c' (Val a lx m) = setVal' c' $ Val a lx $ cancelMapping =<< m

            cancelMapping :: Mapping SimplePropagator a -> [Mapping SimplePropagator a]
            cancelMapping m@(Mapping c' i lx) = case c =~~= c' of
                Just Refl -> pure . Mapping c' i $ delVar l lx
                Nothing   -> pure m


instance PropagatorEqMonad SimplePropagator where
    iso :: forall a b. (Ord a, Meet a, Ord b, Meet b)
        => Cell SimplePropagator a -> Cell SimplePropagator b -> (a <-> b) -> SimplePropagator ()
    iso a b i = do
        va <- getVal' a
        vb <- getVal' b
        iso' va vb
      where
        iso' :: CellVal SimplePropagator a -> CellVal SimplePropagator b -> SimplePropagator ()
        iso' (Ref refA i') _ = iso refA b $ i . i'
        iso' _ (Ref refB i') = iso a refB $ co i' . i
        iso' (Val av alx am) (Val bv blx bm) = case a =~~= b of
            Just Refl -> pure () -- already equal. we assume that i = id
            Nothing   -> do
                setVal' a $ Val av alx (am <> [Mapping b (co i) blx] <> fmap moveMapping bm)
                setVal' b $ Ref a i
                write a (from i bv)

        moveMapping (Mapping ref i' lx) = Mapping ref (co i . i') lx
