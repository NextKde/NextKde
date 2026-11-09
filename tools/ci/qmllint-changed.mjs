#!/usr/bin/env node
// Working-tree changes by default; --base <commit> for PRs; --all for a full scan.
import { lint } from './qml-lint-common.mjs';
lint(process.argv.slice(2));
