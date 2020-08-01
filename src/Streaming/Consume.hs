{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | This module provides all functions that take input streams
-- but do not return output streams.
module Streaming.Consume
  ( -- * Consuming streams of elements
  -- ** IO Consumers
    stdoutLn
  , stdoutLn'
  , print
  , toHandle
  , writeFile
  -- ** Basic Pure Consumers
  , effects
  , erase
  , drained
  , mapM_
  -- ** Folds
  --, fold
  --, fold_
  --, foldM
  --, foldM_
  --, all
  --, all_
  --, any
  --, any_
  --, sum
  --, sum_
  --, product
  --, product_
  --, head
  --, head_
  --, last
  --, last_
  --, elem
  --, elem_
  --, notElem
  --, notElem_
  --, length
  --, length_
  --, toList
  --, toList_
  --, mconcat
  --, mconcat_
  --, minimum
  --, minimum_
  --, maximum
  --, maximum_
  --, foldrM
  --, foldrT
  ) where

import Streaming.Type
import Streaming.Process
import System.IO.Linear
import System.IO.Resource
import Prelude.Linear ((&), ($), (.))
import Prelude (String, Show(..), FilePath)
import Data.Unrestricted.Linear
import qualified Data.Text as Text
import Data.Functor.Identity
import qualified System.IO as System
import Control.Monad.Linear.Builder (BuilderType(..), monadBuilder)
import qualified Control.Monad.Linear as Control


-- #  IO Consumers
-------------------------------------------------------------------------------

-- Note: crashes on a broken output pipe
stdoutLn :: Stream (Of String) IO () #-> IO ()
stdoutLn stream = stdoutLn' stream

stdoutLn' :: Stream (Of String) IO r #-> IO r
stdoutLn' stream = stream & \case
  Return r -> return r
  Effect ms -> ms >>= stdoutLn'
  Step (str :> stream) -> do
    fromSystemIO $ System.putStrLn str
    stdoutLn' stream
  where
    Builder{..} = monadBuilder

print :: Show a => Stream (Of a) IO r #-> IO r
print = stdoutLn' . map show

-- | Write a stream to a handle and close that handle.
toHandle :: Handle #-> Stream (Of String) RIO r #-> RIO r
toHandle handle stream = stream & \case
  Return r -> hClose handle >> return r
  Effect ms -> ms >>= toHandle handle
  Step (str :> stream') -> do
    handle' <- hPutStrLn handle (Text.pack str)
    toHandle handle' stream'
  where
    Builder{..} = monadBuilder

-- | Write a stream to a handle and return the new handle.
toHandle' :: Handle #-> Stream (Of String) RIO r #-> RIO (r, Handle)
toHandle' handle stream = stream & \case
  Return r -> return (r, handle)
  Effect ms -> ms >>= toHandle' handle
  Step (str :> stream') -> do
    handle' <- hPutStrLn handle (Text.pack str)
    toHandle' handle' stream'
  where
    Builder{..} = monadBuilder

writeFile :: FilePath -> Stream (Of String) RIO r -> RIO r
writeFile filepath stream = do
  handle <- openFile filepath System.WriteMode
  toHandle handle stream
  where
    Builder{..} = monadBuilder


-- #  Basic Pure Consumers
-------------------------------------------------------------------------------

effects :: CMonad m => Stream (Of a) m r #-> m r
effects stream = stream & \case
  Return r -> return r
  Effect ms -> ms >>= effects
  Step (_ :> stream') -> effects stream'
  where
    Builder{..} = monadBuilder

erase :: CMonad m => Stream (Of a) m r #-> Stream Identity m r
erase stream = stream & \case
  Return r -> Return r
  Step (_ :> stream') -> Step $ Identity (erase stream')
  Effect ms -> Effect $ ms >>= (return . erase)
  where
    Builder{..} = monadBuilder

drained :: (CMonad m, CMonad (t m), CFunctor (t m), Control.MonadTrans t) =>
  t m (Stream (Of a) m r) #-> t m r
drained = Control.join . Control.fmap (Control.lift . effects)

mapM_ :: (Consumable b, CMonad m) => (a -> m b) -> Stream (Of a) m r #-> m r
mapM_  f stream = stream & \case
  Return r -> return r
  Effect ms -> ms >>= mapM_ f
  Step (a :> stream') -> do
    b <- f a
    return $ consume b
    mapM_ f stream'
  where
    Builder{..} = monadBuilder


-- #  Folds
-------------------------------------------------------------------------------






