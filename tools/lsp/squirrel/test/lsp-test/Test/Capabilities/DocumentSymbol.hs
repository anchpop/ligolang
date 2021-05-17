module Test.Capabilities.DocumentSymbol
  ( unit_document_symbols_example_heap
  , unit_document_symbols_example_access
  ) where

import AST.Scope (Fallback)

import Test.Common.Capabilities.DocumentSymbol
import Test.HUnit (Assertion)

unit_document_symbols_example_heap :: Assertion
unit_document_symbols_example_heap = documentSymbolsExampleHeapDriver @Fallback

unit_document_symbols_example_access :: Assertion
unit_document_symbols_example_access = documentSymbolsExampleAccessDriver @Fallback
