{-# LANGUAGE NoImplicitPrelude #-}
module Control.Combinator.Logics
    ( disjunctFork
    , disjunctForkDestr
    , disjunctForkPromoter
    , Promoter
    , promoteAction
    ) where

import "base" Prelude hiding ( read )
import "base" Data.Functor
import "base" Control.Monad
import "base" Debug.Trace
import "base" Data.Typeable

import "this" Control.Propagator
import "this" Data.Lattice
import "this" Control.Propagator.Scope


data DisjunctFork i j = DisjunctFork
    { name :: j
    , target :: i
    , index :: Int
    } deriving (Eq, Ord, Show)
instance (Std j, Identifier i a) => Identifier (DisjunctFork i j) a

disjunctFork :: forall i j a m.
             ( MonadProp m
             , Typeable m
             , BoundedJoin a, Identifier i a
             , Std j
             ) => i -> j -> [m ()] -> m ()
disjunctFork goal name ms = disjunctForkDestr goal name (zip ms (repeat $ const $ promote goal)) (void $ write goal bot)

class (Identifier i a) => Promoter i a m | i -> a where
  promoteAction :: Scope -> i -> m ()

disjunctForkPromoter :: forall i j a m.
             ( MonadProp m
             , Typeable m
             , BoundedJoin a
             , Identifier i a
             , Promoter i a m
             , Std j
             ) => i -> j -> [m ()] -> m ()
disjunctForkPromoter goal name ms = disjunctForkDestr goal name (zip ms (repeat $ flip promoteAction goal)) (void $ write goal bot)

disjunctForkDestr :: forall i j a m.
             ( MonadProp m
             , Typeable m
             , BoundedJoin a, Identifier i a
             , Std j
             ) => i -> j -> [(m (), Scope -> m ())] -> m () -> m ()
disjunctForkDestr sucvar name ms finDestr = djfs `forM_` \(djf, (constr , _)) -> do
    scp <- scope
    watch djf $ PropagateWinner (djfsDestr scp) finDestr
    scoped djf $ \_ -> do
        push sucvar djf
        constr
  where
    djfs :: [(DisjunctFork i j, (m (), Scope -> m ()))]
    djfs = zipWith (\n m -> (DisjunctFork name sucvar n, m) ) [0..] ms
    djfsDestr :: Scope -> [(DisjunctFork i j, m ())]
    djfsDestr s = map (\(x,(_,z)) -> (x, z s)) djfs

data PropagateWinner i j m = PropagateWinner [(DisjunctFork i j, m ())] (m ())
  --deriving (Eq, Ord, Show)
instance (Eq i, Eq j) => Eq (PropagateWinner i j m) where
  (PropagateWinner a _) == (PropagateWinner b _) = (fst <$> a) == (fst <$> b)
instance (Ord i, Ord j) => Ord (PropagateWinner i j m) where
  compare (PropagateWinner a _) (PropagateWinner b _) = compare (fst <$> a) (fst <$> b)
instance (Show i, Show j) => Show (PropagateWinner i j m) where
  show (PropagateWinner a _) = (show (fst <$> a))

instance (Std j, Typeable m, MonadProp m, Value a, BoundedJoin a, Identifier i a)
         => Propagator m a (PropagateWinner i j m) where
    propagate (PropagateWinner forks finalDestr) _ = do

        fconts <- fmap join . forM forks $ \(f,m) -> read f <&> \case
            Bot -> []
            _   -> [(f,m)]
        case fconts of
            [(f,m)] -> do
                --target f `eq` f
                scoped f $ const m
            []   -> do
              finalDestr
            _ -> pure ()
