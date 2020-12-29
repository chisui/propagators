module Control.Combinator.Logics where

import "base" Control.Monad

import "this" Control.Propagator.Class
import "this" Data.Lattice


disjunctFork :: (Monad m, PropagatorMonad m, Forkable m, BoundedLattice a, Value a) => Cell m a -> m () -> m () -> m ()
disjunctFork r m1 m2 = do
  rc1 <- newEmptyCell "rc1"
  rc2 <- newEmptyCell "rc2"
  disjunct rc1 rc2 r
  namedFork "f1" $ \lft -> do
    namedWatch r (show r ++ " -> " ++ show rc1) (lft . write rc1)
    m1
  namedFork "f2" $ \lft -> do
    namedWatch r (show r ++ " -> " ++ show rc2) (lft . write rc2)
    m2

--If one of the values becomes bot, the output it set equal to the other value
disjunct :: (Monad m, PropagatorMonad m, BoundedLattice a, Value a) => Cell m a -> Cell m a -> Cell m a -> m (Subscriptions m)
disjunct a b r = do
  unsub1 <- namedWatch a ("disjunct " ++ show a ++ " " ++ show b) (disjunctListener r b)
  unsub2 <- namedWatch b ("disjunct " ++ show b ++ " " ++ show a) (disjunctListener r a)
  return (unsub1 <> unsub2)

--TODO: does not remove subscriptions
disjunctListener :: (Monad m, PropagatorMonad m, BoundedJoin a, Value a) => Cell m a -> Cell m a -> a -> m ()
disjunctListener r ca b
  | b == bot =  void $ eq r ca
  | otherwise = return ()
