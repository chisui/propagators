module Control.Propagator.Scope
    ( Scope
    , pushScope
    , popScope
    , lcp
    ) where

import "base" Data.List
import "base" Data.Function
import "base" GHC.Exts ( IsList(..) )

import "this" Data.Some
import "this" Control.Propagator.Class


newtype Scope = Scope [Some Std]
  deriving newtype (Eq, Ord, Semigroup, Monoid, IsList)
instance Show Scope where
    showsPrec _ = showScope . toList
      where
        showScope [] = showString "/"
        showScope (i : s) = shows s . showsPrec 11 i . showString "/"

pushScope :: Std i => i -> Scope -> Scope
pushScope = mappend . Scope . pure . Some

popScope :: Scope -> Maybe (Some Std, Scope)
popScope = fmap (fmap fromList) . uncons . toList

{-| longest common prefix of two Scopes.

  Let @(l, r, p) = lcp a b@ then @a = p <> l@ and @b = p <> r@.
-}
lcp :: Scope -> Scope -> (Scope, Scope, Scope)
lcp s t = fromList <$> on lcp' toList s t
  where
    lcp' (i : a) (j : b) | i == j = (i :) <$> lcp' a b
    lcp' a b = (fromList a, fromList b, mempty)
