{-# LANGUAGE StrictData #-}
module Control.Propagator.Scope
    ( Scope
    , pattern Root
    , pattern (:/)
    , pushScope
    , popScope
    , parScope
    , lcp
    ) where

import "base" Data.List
import "base" Data.Function
import "base" GHC.Exts ( IsList(..) )
import "base" Data.Maybe

import "hashable" Data.Hashable

import "this" Data.Some
import "this" Control.Propagator.Class


newtype Scope = Scope { segments :: [Some Std] }
  deriving newtype (Eq, Hashable)
{-# COMPLETE Root, (:/) #-}
pattern Root :: Scope
pattern Root <- Scope []
  where Root = Scope []
pattern (:/) :: () => forall a. Std a => Scope -> a -> Scope
pattern s :/ i <- (popScope -> Just (Some i, s))
  where s :/ i = Scope (Some i : segments s)

instance IsList Scope where
    type Item Scope = Some Std
    toList (Scope l) = reverse l
    fromList = Scope . reverse
instance Semigroup Scope where
    Scope a <> Scope b = Scope (b <> a)
instance Monoid Scope where
    mempty = Root
instance Ord Scope where
    compare = compare `on` toList
instance Show Scope where
    showsPrec _ = showScope . toList
      where
        showScope :: [Some Std] -> ShowS
        showScope [] = showString "/"
        showScope (i : s)
            = showString "/"
            . extractSome (showsPrec 11) i
            . showScope s

pushScope :: Std i => i -> Scope -> Scope
pushScope = flip mappend . Scope . pure . Some

popScope :: Scope -> Maybe (Some Std, Scope)
popScope = fmap (fmap Scope) . uncons . segments

parScope :: Scope -> Scope
parScope s = fromMaybe s (snd <$> popScope s)

{-| longest common prefix of two Scopes.

  Let @(l, r, p) = lcp a b@ then @a = p <> l@ and @b = p <> r@.
-}
lcp :: Scope -> Scope -> (Scope, Scope, Scope)
lcp s t = fromList <$> on lcp' toList s t
  where
    lcp' (i : a) (j : b) | i == j = (i :) <$> lcp' a b
    lcp' a b = (fromList a, fromList b, mempty)
