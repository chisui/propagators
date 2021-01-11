{-# LANGUAGE NoImplicitPrelude #-}
module Tests.UnificationTest where

import "base" Prelude hiding ( read )
import "base" GHC.Generics
import "base" Debug.Trace

import "this" Data.Terms
import "this" Control.Combinator.Logics
import "this" Control.Propagator
import "this" Control.Propagator.Event ( runSEB )
import "this" Tests.TestLogic
import "this" Data.Lattice


data Cell = STR String | Sv Int | A | B | C deriving (Eq, Ord, Show)
instance Identifier Cell (TermSet Cell)

test1 :: IO ()
test1 = runTestSEB @(TermId Cell) $ do
    sv_a <- fromVarsAsCells (DIRECT A) $ [var (DIRECT $ Sv 0),"a"]
    b_sv <- fromVarsAsCells (DIRECT B) $ ["b", var (DIRECT $ Sv 0)]
    sv_a `eq` b_sv
    return [sv_a, b_sv, DIRECT $ Sv 0]

test2 :: IO ()
test2 = runTestSEB @(TermId Cell) $ do
    t1 <- fromVarsAsCells (DIRECT A) [var $ DIRECT $ Sv 1, "a", var $ DIRECT $ Sv 1]
    t2 <- fromVarsAsCells (DIRECT B) $ [var (DIRECT $ Sv 2), "a"]
    t1 `eq` t2
    return [t1, t2, DIRECT $ Sv 1, DIRECT $ Sv 2]


test3 :: IO ()
test3 = runTestSEB @(TermId Cell) $ do
    t1 <- fromVarsAsCells (DIRECT A) $ var $ DIRECT $ Sv 0
    t2 <- fromVarsAsCells (DIRECT B) $ "a" <> var (DIRECT $ Sv 0)
    t1 `eq` t2
    return [t1, t2, DIRECT $ Sv 0]

test4 :: IO ()
test4 = runTestSEB @(TermId Cell) $ do
    scoped () $ \s -> do
        promote s (DIRECT A)
        write (DIRECT A) "a"
    return [DIRECT A]

data Test4Fork = Test4Fork (TermId Cell) deriving (Eq, Ord, Show)
instance MonadProp m => Propagator m (TermSet (TermId Cell), TermId Cell) Test4Fork where
    propagate (Test4Fork orig) (i, t) = do
      write orig i
      orig `eq` t

test4' :: IO ()
test4' = runTestSEB @(TermId Cell) $ do
    let [orig, t1, t2] = DIRECT <$> [A, B, C] :: [TermId Cell]
    write t1 "A"
    write t2 TSBot
    --TODO: When forking, it might not be the entire term that is being transferred, but only the top node!
    disjunctFork orig (Test4Fork orig) [("A" :: TermSet (TermId Cell), t1), (Bot, t2)]
    return [orig, t1, t2]

testRefreshTo :: IO ()
testRefreshTo = runTestSEB $ do
    orig <- fromVarsAsCells (DIRECT A) ["b", "a"]
    --so the term listeners are placed
    v1 <- fromVarsAsCells (DIRECT C) []
    cpy <- refreshVarsTbl B [("b",v1 :: TermId Cell)] orig
    return [orig, cpy]
{-
testRefreshBack :: IO ()
testRefreshBack = runTestSEB $ do
    --so the term listeners are placed
    orig <- fromVarsAsCells []
    v1 <- fromVarsAsCells []
    copy <- fromVarsAsCells [var v1, "a"]
    refreshVarsTbl [(CUSTOM "b",v1)] orig copy
    return [orig, copy]
-}

testRefreshUnification :: IO ()
testRefreshUnification = runTestSEB @(TermId Cell) $ do
  v1 <- fromVarsAsCells (DIRECT A) []
  v2 <- fromVarsAsCells (DIRECT B) []
  orig <- fromVarsAsCells (DIRECT $ STR "orig")
    [["a", "a"], var v2]
  rule <- fromVarsAsCells (DIRECT $ STR "rule")
    [["b", "a"], "b"]
  cpy <- refreshVarsTbl (STR "copy" ) [("b",v1 :: TermId Cell)] rule
  eq orig cpy
  return [rule, cpy, orig]


data TD = TD_A | TD_B | TD_C
  deriving (Eq, Ord, Show, Generic, Enum, Bounded)

data TC = Orig | TC Int deriving (Eq, Ord, Show)
instance Identifier TC (Domain TD)

test5 :: IO ()
test5 = flip runSEB (>> pure ()) $ do
    write (TC 2) [TD_A, TD_C]

    scoped () $ \s -> watch (TC 2) $ Scoped s $ Write $ TC 2

    watch Orig $ Const ([TD_A] :: Domain TD) $ Write $ TC 2

    pure $ do
        v <- read Orig
        traceM $ show v
