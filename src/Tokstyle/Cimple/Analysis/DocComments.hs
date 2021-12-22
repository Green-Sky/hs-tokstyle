{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData        #-}
module Tokstyle.Cimple.Analysis.DocComments (analyse) where

import           Control.Monad.State.Lazy    (State)
import qualified Control.Monad.State.Lazy    as State
import           Data.Text                   (Text)
import qualified Data.Text                   as Text
import           Language.Cimple             (AlexPosn (..), Lexeme (..),
                                              LexemeClass (..), Node (..))
import           Language.Cimple.Diagnostics (HasDiagnostics (..), warn)
import qualified Language.Cimple.Diagnostics as Diagnostics
import           Language.Cimple.Pretty      (ppTranslationUnit)
import           Language.Cimple.TraverseAst (AstActions (..), defaultActions,
                                              traverseAst)


data Linter = Linter
    { diags :: [Text]
    , docs  :: [(Text, (FilePath, Node (Lexeme Text)))]
    }

empty :: Linter
empty = Linter [] []

instance HasDiagnostics Linter where
    addDiagnostic diag l@Linter{diags} = l{diags = addDiagnostic diag diags}


linter :: AstActions (State Linter) Text
linter = defaultActions
    { doNode = \file node act ->
        case node of
            Commented doc (FunctionDecl _ (FunctionPrototype _ (L _ IdVar fname) _) _) -> do
                checkCommentEquals file doc fname
                act

            Commented doc (FunctionDefn _ (FunctionPrototype _ (L _ IdVar fname) _) _) -> do
                checkCommentEquals file doc fname
                act

            {-
            Commented _ n -> do
                warn file node . Text.pack . show $ n
                act
            -}

            _ -> act
    }
  where
    tshow = Text.pack . show

    removeSloc :: Node (Lexeme a) -> Node (Lexeme a)
    removeSloc = fmap $ \(L _ c t) -> L (AlexPn 0 0 0) c t

    checkCommentEquals file doc fname = do
        l@Linter{docs} <- State.get
        case lookup fname docs of
            Nothing -> State.put l{docs = (fname, (file, doc)):docs}
            Just (_, doc') | removeSloc doc == removeSloc doc' -> return ()
            Just (file', doc') -> do
                warn file (Diagnostics.at doc) $ "comment on definition of `" <> fname
                    <> "' does not match declaration:\n"
                    <> tshow (ppTranslationUnit [doc])
                warn file' (Diagnostics.at doc') $ "mismatching comment found here:\n"
                    <> tshow (ppTranslationUnit [doc'])

analyse :: [(FilePath, [Node (Lexeme Text)])] -> [Text]
analyse tus = reverse . diags $ State.execState (traverseAst linter $ reverse tus) empty
