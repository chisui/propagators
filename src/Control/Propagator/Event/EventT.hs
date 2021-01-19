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
import "base" Control.Monad
import "base" Debug.Trace
import "base" Data.Typeable

import "transformers" Control.Monad.Trans.Reader ( ReaderT(..) )
import "transformers" Control.Monad.Trans.Class

import "mtl" Control.Monad.Reader.Class
import "mtl" Control.Monad.State.Class

import "this" Control.Propagator.Base
import "this" Control.Propagator.Scope
import "this" Control.Propagator.Event.Types
import "this" Control.Propagator.Reflection
import "this" Data.Lattice

import "this" Control.Propagator.Combinators (promote)


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

instance (Typeable m, MonadRef m, MonadEvent (Evt m) m, Monad m) => MonadProp (EventT m) where

    write i a = do
      --read i
      i <$ (fire' $ WriteEvt . Write i a)

    watch i p = do
      read i
      i <$ (fire' $ WatchEvt . Watch i p)

    read i = do
      s <- scope
      --traceM $ "Reading "++ (show i) ++ " in " ++ (show s)
      case popScope s of
        Just (snd -> s') -> do
          --traceM $ "promoting "++show i ++ " to "++show s ++ " from " ++ show s'
          inScope s' $ promote s i
          --inScope s' $ promote s (PropagatorsOf @(EventT m) i)
          void $ inScope s' $ read i
        Nothing -> pure ()
      fmap (fromMaybe Top) . withScope . flip getVal $ i

    scope = ask

    inScope s = local (const s)
