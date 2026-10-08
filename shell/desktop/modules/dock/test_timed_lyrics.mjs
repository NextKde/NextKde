import assert from 'node:assert/strict';
import {parse, indexAt} from './TimedLyrics.mjs';
assert.deepEqual(parse('plain lyrics\nsecond line'), []);
assert.deepEqual(parse('[ar:Artist]\n[00:05]one\n[00:10.25][00:20.250]repeat\n[00:15.000]'), [
    {time:5,text:'one'}, {time:10.25,text:'repeat'}, {time:15,text:''}, {time:20.25,text:'repeat'}]);
assert.deepEqual(parse('[00:02.5] a\r\n[offset:+500]'), [{time:2,text:'a'}]);
assert.deepEqual(parse('[offset:-500]\n[00:02]a'), [{time:2.5,text:'a'}]);
assert.deepEqual(parse('[00:99]invalid'), []);
const lines=parse('[00:20]last\n[00:01]first\n[00:10]');
for (const [position,expected] of [[0,-1],[1,0],[15,1],[21,2],[2,0],[10,1],[NaN,-1]])
    assert.equal(indexAt(lines,position),expected);
assert.equal(indexAt([],100),-1);
console.log('Timed lyrics: timestamps, repeats, offsets, interludes and seeks passed');
