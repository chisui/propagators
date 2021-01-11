{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE NoImplicitPrelude    #-}
{-# LANGUAGE StrictData           #-}
module Control.Propagator.Event.EventT
    ( Evt
    , EventT(..)
    , MonadEvent(..)
    , MonadRef(..)
    ) where

import "base" Prelude hiding ( read )
import "base" Data.Maybe

import "transformers" Control.Monad.Trans.Reader ( ReaderT(..) )
import "transformers" Control.Monad.Trans.Class

import "mtl" Control.Monad.Reader.Class
import "mtl" Control.Monad.State.Class

import "this" Control.Propagator.Base
import "this" Control.Propagator.Scope
import "this" Control.Propagator.Event.Types
import "this" Data.Lattice


type Evt m = Event (EventT m)

class Monad m => MonadEvent e m | m -> e where
    fire :: e -> m ()

class Monad m => MonadRef m where
    getVal :: Identifier i a => Scope -> i -> m (Maybe a)

newtype EventT m a = EventT
    { runEventT :: ReaderT Scope m a
    }
  deriving newtype (Functor, Applicative, Monad, MonadFail, MonadReader Scope)
deriving newtype instance MonadState s m => MonadState s (EventT m)

instance MonadTrans EventT where
    lift = EventT . lift

withScope :: Monad m => (Scope -> m a) -> EventT m a
withScope f = ask >>= lift . f

fire' :: MonadEvent (Evt m) m => (Scope -> Evt m) -> EventT m ()
fire' ctr = withScope $ fire . ctr

instance (MonadRef m, MonadEvent (Evt m) m, Monad m) => MonadProp (EventT m) where
    
    write i a = i <$ (fire' $ WriteEvt . Write i a)
    
    watch i p = i <$ (fire' $ WatchEvt . Watch i p)

    read = fmap (fromMaybe top) . withScope . flip getVal

    scope = ask

    inScope s = local (const s)
