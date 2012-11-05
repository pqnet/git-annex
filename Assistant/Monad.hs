{- git-annex assistant monad
 -
 - Copyright 2012 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

{-# LANGUAGE PackageImports, GeneralizedNewtypeDeriving, MultiParamTypeClasses #-}

module Assistant.Monad (
	Assistant,
	AssistantData(..),
	newAssistantData,
	runAssistant,
	getAssistant,
	liftAnnex,
	(<~>),
	(<<~),
	asIO,
	asIO1,
	asIO2,
) where

import "mtl" Control.Monad.Reader
import Control.Monad.Base (liftBase, MonadBase)

import Common.Annex
import Assistant.Types.ThreadedMonad
import Assistant.Types.DaemonStatus
import Assistant.Types.ScanRemotes
import Assistant.Types.TransferQueue
import Assistant.Types.TransferSlots
import Assistant.Types.Pushes
import Assistant.Types.BranchChange
import Assistant.Types.Commits
import Assistant.Types.Changes
import Assistant.Types.Buddies
import Assistant.Types.NetMessager

newtype Assistant a = Assistant { mkAssistant :: ReaderT AssistantData IO a }
	deriving (
		Monad,
		MonadIO,
		MonadReader AssistantData,
		Functor,
		Applicative
	)

instance MonadBase IO Assistant where
	liftBase = Assistant . liftBase

data AssistantData = AssistantData
	{ threadName :: String
	, threadState :: ThreadState
	, daemonStatusHandle :: DaemonStatusHandle
	, scanRemoteMap :: ScanRemoteMap
	, transferQueue :: TransferQueue
	, transferSlots :: TransferSlots
	, failedPushMap :: FailedPushMap
	, commitChan :: CommitChan
	, changeChan :: ChangeChan
	, branchChangeHandle :: BranchChangeHandle
	, buddyList :: BuddyList
	, netMessagerControl :: NetMessagerControl
	}

newAssistantData :: ThreadState -> DaemonStatusHandle -> IO AssistantData
newAssistantData st dstatus = AssistantData
	<$> pure "main"
	<*> pure st
	<*> pure dstatus
	<*> newScanRemoteMap
	<*> newTransferQueue
	<*> newTransferSlots
	<*> newFailedPushMap
	<*> newCommitChan
	<*> newChangeChan
	<*> newBranchChangeHandle
	<*> newBuddyList
	<*> newNetMessagerControl

runAssistant :: Assistant a -> AssistantData -> IO a
runAssistant a = runReaderT (mkAssistant a)

getAssistant :: (AssistantData -> a) -> Assistant a
getAssistant = reader

{- Runs an action in the git-annex monad. Note that the same monad state
 - is shared amoung all assistant threads, so only one of these can run at
 - a time. Therefore, long-duration actions should be avoided. -}
liftAnnex :: Annex a -> Assistant a
liftAnnex a = do
	st <- reader threadState
	liftIO $ runThreadState st a

{- Runs an IO action, passing it an IO action that runs an Assistant action. -}
(<~>) :: (IO a -> IO b) -> Assistant a -> Assistant b
io <~> a = do
	d <- reader id
	liftIO $ io $ runAssistant a d

{- Creates an IO action that will run an Assistant action when run. -}
asIO :: Assistant a -> Assistant (IO a)
asIO a = do
	d <- reader id
	return $ runAssistant a d

asIO1 :: (a -> Assistant b) -> Assistant (a -> IO b)
asIO1 a = do
	d <- reader id
	return $ \v -> runAssistant (a v) d

asIO2 :: (a -> b -> Assistant c) -> Assistant (a -> b -> IO c)
asIO2 a = do
	d <- reader id
	return $ \v1 v2 -> runAssistant (a v1 v2) d

{- Runs an IO action on a selected field of the AssistantData. -}
(<<~) :: (a -> IO b) -> (AssistantData -> a) -> Assistant b
io <<~ v = reader v >>= liftIO . io