# Elm extension qualification fixture

`src/Rules.elm` is one Elm module for `mise run test:cli-extension-elm`. The Elm
extension `v0.4.1` does not claim `multiDocument`, so the fixture is one
document. Its module name has one segment because the extension compiles only
module names that its package name does not prefix.
