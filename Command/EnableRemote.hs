{- git-annex command
 -
 - Copyright 2013 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Command.EnableRemote where

import Common.Annex
import Command
import qualified Logs.Remote
import qualified Types.Remote as R
import qualified Command.InitRemote as InitRemote

import qualified Data.Map as M

def :: [Command]
def = [command "enableremote"
	(paramPair paramName $ paramOptional $ paramRepeating paramKeyValue)
	seek SectionSetup "enables use of an existing special remote"]

seek :: [CommandSeek]
seek = [withWords start]

start :: [String] -> CommandStart
start [] = unknownNameError "Specify the name of the special remote to enable."
start (name:ws) = go =<< InitRemote.findExisting name
  where
	config = Logs.Remote.keyValToConfig ws
	
  	go Nothing = unknownNameError "Unknown special remote name."
	go (Just (u, c)) = do
		let fullconfig = config `M.union` c	
		t <- InitRemote.findType fullconfig

		showStart "enableremote" name
		next $ perform t u fullconfig

unknownNameError :: String -> Annex a
unknownNameError prefix = do
	names <- InitRemote.remoteNames
	error $ prefix ++
		if null names
			then ""
			else " Known special remotes: " ++ intercalate " " names

perform :: RemoteType -> UUID -> R.RemoteConfig -> CommandPerform
perform t u c = do
	c' <- R.setup t u c
	next $ cleanup u c'

cleanup :: UUID -> R.RemoteConfig -> CommandCleanup
cleanup u c = do
	Logs.Remote.configSet u c
	return True
