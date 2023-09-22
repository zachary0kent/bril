import Bril.CFG (IsCFG, IsNode, NodeOf)
import Bril.CFG qualified as CFG
import Bril.CFG.ByInstr qualified as ByInstr
import Bril.Dominator qualified as Dom
import Bril.Func (Func)
import Bril.Func qualified as Func
import Bril.Parse
import Bril.Program (Program (..))
import Control.Monad (forM_)
import Data.Function ((&))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.String (fromString)
import Data.Traversable (forM)
import System.FilePath.Glob
import System.Process
import Test.Hspec

-- | @dominators cfg@ is an association list mapping every node to the
-- set of nodes that dominate it, using a naive algorithm. Used as a
-- reference implementation for hspec
dominators :: (IsCFG g, Ord (NodeOf g)) => g -> [(NodeOf g, Set (NodeOf g))]
dominators cfg = map (\b -> (b, dominatorsForNode b)) allNodes
  where
    allNodes = CFG.nodes cfg
    dominatorsForNode b = Set.fromList $ filter (`dom` b) allNodes
    dom a b =
      case CFG.start cfg of
        Nothing -> True
        Just start ->
          if b == start
            then a == start
            else not $ b `Set.member` CFG.reachableExcluding cfg (Set.singleton a) start

-- | Construct a dominator tree naively as a reference implementation
dominatorTree :: (IsCFG g, IsNode (NodeOf g), Ord (NodeOf g)) => g -> Dom.Tree (NodeOf g)
dominatorTree g =
  case CFG.start g of
    Nothing -> Dom.Empty
    Just start -> Dom.Root $ build (Set.toList $ CFG.reachable start g) start
  where
    Dom.Relations {idom} = Dom.relations g
    build univ node =
      Dom.Node
        { node,
          children =
            univ
              & filter (node `idom`)
              & map (build univ)
              & Set.fromList
        }

-- | @verifyDominators cfg@ returns `True` iff the dataflow implementation
-- of dominators agrees with the naive, slow implementation of dominators
verifyDominators :: (Ord (NodeOf g), IsNode (NodeOf g), IsCFG g) => g -> Bool
verifyDominators g =
  all (\(node, doms) -> doms == testDominators node) $ dominators g
  where
    testDominators = Dom.dominators g

verifyDominatorsForFunction :: Func -> Bool
verifyDominatorsForFunction func =
  func
    & Func.instrs
    & ByInstr.fromList
    & verifyDominators

verifyDominatorsForProgram :: Program -> Bool
verifyDominatorsForProgram (Program funcs) = all verifyDominatorsForFunction funcs

-- | @verifyDominatorTree cfg@ returns `True` iff the reference and test
-- implementations of dominator trees agree
verifyDominatorTree :: (Ord (NodeOf g), IsNode (NodeOf g), IsCFG g) => g -> Bool
verifyDominatorTree g = dominatorTree g == Dom.tree g

verifyDominatorTreeForFunction :: Func -> Bool
verifyDominatorTreeForFunction func =
  func
    & Func.instrs
    & ByInstr.fromList
    & verifyDominatorTree

verifyDominatorTreesForProgram :: Program -> Bool
verifyDominatorTreesForProgram (Program funcs) = all verifyDominatorTreeForFunction funcs

dominatorTests :: [(String, Program)] -> SpecWith ()
dominatorTests progs =
  describe "Test Dominators" do
    forM_ progs \(path, prog) -> do
      it ("dominators for " ++ path) do
        verifyDominatorsForProgram prog `shouldBe` True

dominatorTreeTests :: [(String, Program)] -> SpecWith ()
dominatorTreeTests progs =
  describe "Test Dominator Trees" do
    forM_ progs \(path, prog) -> do
      it ("dominator trees for " ++ path) do
        verifyDominatorTreesForProgram prog `shouldBe` True

-- | Associate every benchmark file path with its parsed Bril program
parsePrograms :: IO [(String, Program)]
parsePrograms = do
  paths <- glob "../benchmarks/*/*.bril"
  forM paths \path -> do
    bril <- readProcess "cat" [path] []
    json <- readProcess "bril2json" [] bril
    prog <- decodeProgram $ fromString json
    pure (path, prog)

main :: IO ()
main = do
  progs <- parsePrograms
  hspec $ describe "dominance utilities" do
    dominatorTests progs
    dominatorTreeTests progs
