{-# LANGUAGE NoImplicitPrelude #-}
module Control.Combinator.Logics
    ( disjunctFork
    ) where

import "base" Prelude hiding ( read )

import "base" Control.Monad
import "base" Debug.Trace

import "this" Control.Propagator.Class
import "this" Control.Propagator.Combinators
import "this" Data.Lattice
import "this" Control.Util

{-
--TODO: does not delete listeners
disjunctForkList :: (Monad m, MonadProp m, Forkable m, BoundedLattice a, Value a) => Cell m a -> [m ()] -> m ()
disjunctForkList _ [] = return ()
disjunctForkList c [m] = do
  fork (\lft -> do
    namedWatch c ("->"++show c) (lft.(write c))
    m
    )
disjunctForkList c mlst = do
  ms <- forM mlst (\m -> do
    rc <- newEmptyCell "rc"
    return (rc, m))
  case ms of
    ((rc1,_):(rc2,_):rms) -> do
      void $ namedWatch rc1 "rc1mult" $ disjunctMultiListener c (rc1:rc2:(fst <$> rms))
      void $ namedWatch rc2 "rc2mult" $ disjunctMultiListener c (rc1:rc2:(fst <$> rms))
      forM_ ms (\(rc, m) -> namedFork "rcf" (\lft -> do
        namedWatch c "c->rc" (lft.(write rc))
        m
        ))
    _ -> error "list should have at least two elements!"
-}

data DisjunctFork w i = Rc w Int i deriving (Eq, Ord, Show)
instance (Std w, Identifier i a) => Identifier (DisjunctFork w i) a

disjunctFork :: (MonadProp m, Forkable m, BoundedJoin a, Identifier i a, Std w) => w -> i -> [m ()] -> m ()
disjunctFork _ _ [] = pure ()
disjunctFork idfr tg [m] =
  fork ("disjunct" :: String, Rc idfr 0 tg) (\lft -> do
      watch tg ("disjunct" :: String, Rc idfr 0 tg) (void.lft.(write tg)) >> m
    )
disjunctFork idfr tg ms = do --ms has at least 2 elements
    watch (Rc idfr 0 tg) ()
      (disjunctForkMultiListener tg rcs)
    watch (Rc idfr 1 tg) ()
      (disjunctForkMultiListener tg rcs)
    sequence_ $ zipWith disjunctFork' rcs ms
  where rcs = [Rc idfr i tg | i <- [0..length ms - 1]]
        disjunctFork' i m = do
            fork ("disjunct" :: String, i) $ \lft -> do
              watch tg () (lft . write i) >> m

disjunctForkMultiListener :: (MonadProp m, BoundedJoin a, Identifier i a, Std w) => i -> [DisjunctFork w i] -> a -> m ()
disjunctForkMultiListener _ [] _ = pure ()
disjunctForkMultiListener tg forks _ = do
  fconts <- mapM read forks
  let
    fctf = zip fconts forks
    sucf = filter ((/= bot).fst) fctf
    in do
      traceM $ "sucf:" ++ (show sucf)
      if isSingleton sucf
          then eq tg (snd $ head sucf)
          else pure ()

{-
disjunctFork r = sequence_ . zipWith disjunctFork' [Rc i r | i <- [0..]]
  where
    disjunctFork' i m = do
        watch i ("disjunct" :: String, i) (disjunctListener r i)
        fork ("disjunct" :: String, i) $ \lft -> watch r i (lft . write i) >> m

disjunctListener :: (MonadProp m, BoundedJoin a, Identifier i a) => i -> DisjunctFork i -> a -> m ()
disjunctListener r ca b
    | b == bot  = void $ eq r ca
    | otherwise = pure ()
-}
