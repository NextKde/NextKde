#!/usr/bin/env node
// Use Qt's parser rather than a brace/line heuristic: strings, comments,
// sibling objects and multiple declarations on one line must be handled correctly.
import { lint } from './qml-lint-common.mjs';
lint(process.argv.slice(2), true);
