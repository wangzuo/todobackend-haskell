{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE OverloadedStrings #-}
module TodoBackend.Model where

import Control.Applicative ((<$>), (<*>))
import Control.Monad (mzero)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Logger
import Control.Monad.Trans.Resource (runResourceT, ResourceT)
import Data.Aeson
import Data.Maybe (fromMaybe)
import qualified Database.Persist.Class as DB
import qualified Database.Persist.Sqlite as Sqlite
import qualified Data.Text as Text
import Database.Persist.TH
import Web.PathPieces

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Todo
    title String
    completed Bool
    order Int
    deriving Show
|]

instance ToJSON (Sqlite.Entity Todo) where
  toJSON entity = object
      [ "id" .= key
      , "url" .= ("http://todobackend-scotty.herokuapp.com/todos/" ++ keyText)
      , "title" .= todoTitle val
      , "completed" .= todoCompleted val
      , "order" .= todoOrder val
      ]
    where
      key = Sqlite.entityKey entity
      val = Sqlite.entityVal entity
      keyText = Text.unpack $ toPathPiece key


data TodoAction = TodoAction
  { actTitle :: Maybe String
  , actCompleted :: Maybe Bool
  , actOrder :: Maybe Int
  } deriving Show

instance FromJSON TodoAction where
  parseJSON (Object o) = TodoAction
    <$> o .:? "title"
    <*> o .:? "completed"
    <*> o .:? "order"
  parseJSON _ = mzero

instance ToJSON TodoAction where
  toJSON (TodoAction mTitle mCompl mOrder) = noNullsObject
      [ "title"     .= mTitle
      , "completed" .= mCompl
      , "order"     .= mOrder
      ]
    where
      noNullsObject = object . filter notNull
      notNull (_, Null) = False
      notNull _         = True

actionToTodo :: TodoAction -> Todo
actionToTodo (TodoAction mTitle mCompleted mOrder) = Todo title completed order
  where
    title     = fromMaybe "" mTitle
    completed = fromMaybe False mCompleted
    order     = fromMaybe 0 mOrder

actionToUpdates :: TodoAction -> [Sqlite.Update Todo]
actionToUpdates act =  updateTitle
                    ++ updateCompl
                    ++ updateOrd
  where
    updateTitle = maybe [] (\title -> [TodoTitle Sqlite.=. title])
                  (actTitle act)
    updateCompl = maybe [] (\compl -> [TodoCompleted Sqlite.=. compl])
                  (actCompleted act)
    updateOrd = maybe [] (\ord -> [TodoOrder Sqlite.=. ord])
                  (actOrder act)

runDb :: Sqlite.SqlPersistT (ResourceT (NoLoggingT IO)) a -> IO a
runDb = runNoLoggingT . runResourceT . Sqlite.withSqliteConn "dev.sqlite3" . Sqlite.runSqlConn
