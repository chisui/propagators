{-# LANGUAGE NoImplicitPrelude #-}
module Control.Language.LogLang where

import "base" Prelude hiding ( read )
import "base" GHC.Exts
import "base" Control.Monad
import "base" Data.Typeable
import "base" Debug.Trace

import "containers" Data.Map qualified as Map
import "containers" Data.Set (Set)
import "containers" Data.Set qualified as Set

import "this" Data.Terms
import "this" Control.Combinator.Logics
import "this" Control.Propagator
import "this" Control.Propagator.Propagator
import "this" Control.Propagator.Combinators
import "this" Data.Lattice


type Clause = []

type Consts = Set.Set TermConst

--clauses need to memorise their universal variables
type KB i = [(Consts, Clause i)]

splitClause :: Clause i -> Maybe (Clause i, i)
splitClause [] = Nothing
splitClause cl = Just (init cl, last cl)

refreshClause ::
  ( MonadProp m
  , Identifier i (TermSet i)
  , CopyTermId i
  , Bound i
  , Std w) =>
  w -> (Consts, Clause i) -> m (Clause i)
refreshClause lsid (binds, trms)
    = forM (zip trms [0..]) $ \(t,i) ->
        refreshVarsTbl (lsid,i::Int) (Map.fromSet (bound lsid) binds) t

data SimpleKBNetwork w i = SBNC w i
  deriving (Eq, Ord, Show)
instance (Std w, Std i) => Identifier (SimpleKBNetwork w i) ()

data Lower w i = LW w i | LWDirect w
  deriving (Eq, Ord, Show)

simpleKBNetwork ::
  ( MonadProp m
  , MonadFail m
  , Typeable m
  , Identifier i (TermSet i)
  , Promoter i (TermSet i) m
  , Bound i
  , CopyTermId i
  , Std w) =>
  w -> KB i -> i -> m ()
simpleKBNetwork = simpleKBNetwork' (-1)


simpleKBNetwork' :: forall m i w .
  ( MonadProp m
  , MonadFail m
  , Typeable m
  , Identifier i (TermSet i)
  , Promoter i (TermSet i) m
  , Bound i
  , CopyTermId i
  , Std w) =>
  Int -> w ->  KB i -> i -> m ()
simpleKBNetwork' fuel listId kb goal = simpleKBNetwork'' fuel listId kb goal goal

--TODO, WARNING: empty clauses!
--TODO: Proper indices!
simpleKBNetwork'' :: forall m i w .
  ( MonadProp m
  , MonadFail m
  , Typeable m
  , Identifier i (TermSet i)
  , Promoter i (TermSet i) m
  , Bound i
  , CopyTermId i
  , Std w) =>
  Int -> w ->  KB i -> i -> i -> m ()
simpleKBNetwork'' 0 _ _ _ _ = return ()
simpleKBNetwork'' fuel listId kb goal origGoal = watchFixpoint listId $ do
    g <- read goal
    unless (g==bot) $ do
        --traceM $ "Executing branch "++show listId
        disjunctForkPromoter goal ("disjunctForkPromoter"::String, listId, goal) $
          (flip (zipWith ($))) [0..] $ [\i -> do

            requestTerm goal
            requestTerm origGoal
            forM_ kb (\(_,clause) ->
              forM_ clause requestTerm)

            (splitClause -> Just (pres, post)) <- refreshClause ("copy" :: String, listId, i::Int) cls

            watchTermRec goal
            eq post goal

            let {traceSolution = watchFixpoint (listId, i) $ ((do
              g' <- read origGoal
              unless (g' == bot) $ do
                og <- fromCellSize 100 origGoal
                traceM $ "Possible solution on fixpoint: "++{-show (listId, i)++ -}"\n"++show og
                watchFixpoint (listId, i) traceSolution
            ) :: m ())}
            when (null pres) $ watchTermRec origGoal >> requestTerm origGoal >> traceSolution

            forM_ (zip pres [0..]) $ \(p,j) -> do
              simpleKBNetwork'' (fuel-1) ("simpleKBNetwork''"::String,(fuel-1),p,j::Int,listId,i) kb p origGoal --TODO: pack the kb
              propBot p goal
          |cls <- kb] ++ [\i -> do
            requestTerm goal
            scoped (listId,i) $ const $ do
              requestTerm goal
              eqt <- fromVarsAsCells (listId,i,"vacr"::String) [var (listId,i,"left"::String),"/=",var (listId,i,"right"::String)]
              goal `eq` eqt
              watchFixpoint (listId,i,"checkEq"::String) $ do
                gl <- read goal
                unless (isBot gl) $ do
                  eqt2 <- fromVarsAsCells (listId,i,"vacr2"::String) [var (listId,i,"eq"::String),"/=",var (listId,i,"eq"::String)]
                  goal `eq` eqt2
                  watchFixpoint (listId,i,"checkEqCont"::String) $ do
                    unless (isBot goal) $ do
                      --goal needs to have failed in the fixpoint. Otherwise this branch fails.
                      write goal bot
                      promote goal

          ]


{-
--This is the split and e.f.q., but only for the statement (a = b) -> bot
scoped (listId,i) $ do
  eqt <- fromVarsAsCells (listId,i) [(listId,i,"eq"::String),"=",(listId,i,"eq"::String)]
  imp <- fromVarsAsCells (listId,i) [[(listId,i,"eq"::String),"=",(listId,i,"eq"::String)],["->","bot"]]
  goal `eq` eqt

-}








--
