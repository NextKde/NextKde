import QtQuick
import QtTest
import ListenFree.Native 1.0
import "Components"

Item {
    width: 900; height: 700
    Rectangle { anchors.fill: parent; color: "#283343" }
    MouseArea { anchors.fill: parent; onWheel: wheel => wheel.accepted = true }
    LyricsPanel { id: panel; x: 100; y: 30; width: 650; height: 670; artworkBackground: true }
    LyricTextMetrics { id: metrics }
    SpringValue { id: springProbe }
    Text { id: fontProbe; visible: false; font.family: "Segoe UI"; font.pixelSize: 30; font.weight: Font.DemiBold }
    TestCase {
        name: "ClassicLyricsMotion"
        when: windowShown
        function fixture() {
            const lines = []
            for (let i=0;i<24;++i) lines.push({text:"Keep this moment 停留",timeMs:i*4000,translation:"让这一刻停留",
                words:[{text:"Keep this moment ",startMs:i*4000,endMs:i*4000+400},
                       {text:"停留",startMs:i*4000+400,endMs:i*4000+3400}]})
            return lines
        }
        function init() {
            panel.animationActive = false
            panel.reducedMotion = false
            panel.playing = false
            panel.inactiveBlurEnabled = true
            panel.karaokeEnabled = true
            panel.visible = true
            panel.width = 650
            panel.fontSize = 28
            panel.alignmentMode = "Center"
            panel.lyrics = fixture()
            panel.currentLineIndex = 3
            panel.positionMs = 12500
            panel.notifySeek()
            wait(100)
        }
        function effectCounts(item) {
            let glyphs=String(item.objectName).indexOf("lyricGrapheme")===0?1:0
            let textures=String(item.objectName).indexOf("lyricEmphasisTexture")===0?1:0
            const children=item.children || []
            for(let i=0;i<children.length;++i) {
                const child=effectCounts(children[i]);glyphs+=child.glyphs;textures+=child.textures
            }
            return {glyphs:glyphs,textures:textures}
        }
        function test_effect_budget() {
            panel.animationActive=true
            wait(500)
            const single=effectCounts(panel)
            compare(single.glyphs,2)
            compare(single.textures,1,"Two glyphs share one shaped token texture")
            panel.currentLineIndex=4
            panel.positionMs=16500
            wait(80)
            const overlap=effectCounts(panel)
            compare(overlap.glyphs,4)
            compare(overlap.textures,2,"Only current/outgoing words retain emphasis textures")
            panel.animationActive=false
            wait(50)
            compare(effectCounts(panel).textures,0)
            compare(effectCounts(panel).glyphs,0)
        }
        function test_graphemes_and_merged_syllables() {
            const font = fontProbe.font
            const tokens = metrics.prepare([
                {text:"sta",startMs:0,endMs:700},
                {text:"ying ",startMs:700,endMs:1800},
                {text:"A\u0301👩‍👩‍👧‍👦",startMs:1800,endMs:4800}],font)
            compare(tokens[0].emphasized,true)
            compare(tokens[0].groupCount,7)
            compare(tokens[1].charOffset,3)
            compare(tokens[0].emphasisDuration,tokens[1].emphasisDuration)
            compare(tokens[2].glyphs.length,2,"Combining accents and ZWJ emoji stay intact")
            compare(tokens[2].emphasized,false,"Long UTF-16 token must not qualify merely because it is long")
            const cjk = metrics.prepare([{text:"𠀀𠀁𠀂𠀃",startMs:0,endMs:1600}],font)
            compare(cjk[0].emphasized,true,"Supplementary CJK follows CJK duration rule")
            compare(cjk[0].glyphs.length,4)
        }
        function test_long_word_stagger_and_static_width() {
            panel.animationActive = true
            wait(550)
            const a=findChild(panel,"lyricGrapheme3/1/0"), b=findChild(panel,"lyricGrapheme3/1/1")
            verify(a);verify(b)
            const row=findChild(panel,"lyricRow3"), base=findChild(panel,"lyricWord3/1")
            const width=base.implicitWidth, height=row.height
            panel.positionMs=13600
            wait(100)
            verify(a.envelope>b.envelope,"Characters must not pulse in unison")
            verify(a.scale>1.01,"Long tone expands")
            verify(a.glowAlpha>0,"Long tone gains a local glow")
            compare(base.implicitWidth,width)
            compare(row.height,height,"Transforms cannot change row layout")
            const held=a.scale
            wait(200)
            compare(a.scale,held,"Paused media time freezes the emphasis")
            panel.positionMs=19000
            wait(100)
            verify(!findChild(panel,"lyricGrapheme3/1/0"),"Finished long tones release their glyph effects")
            compare(base.y,-panel.fontSize*.05,"Native text preserves the completed float position")
            panel.reducedMotion=true
            wait(50)
            verify(!findChild(panel,"lyricGrapheme3/1/0"),"Reduced motion releases glyph effects")
        }
        function test_wheel_holds_visual_focus() {
            const list=findChild(panel,"lyricList")
            const initial=list.contentY
            mouseWheel(panel,300,300,0,-240)
            wait(200)
            verify(Math.abs(list.contentY-initial)>10)
            const position=list.contentY
            compare(panel.focusLineIndex,3)
            panel.currentLineIndex=5
            wait(300)
            compare(panel.focusLineIndex,3,"Browsing freezes focus as well as scroll")
            compare(list.contentY,position)
            compare(panel.touchBrowsing,false,"Discrete wheel does not clear inactive blur")
            wait(5200)
            compare(panel.focusLineIndex,5)
            verify(Math.abs(list.contentY-position)>10)
        }
        function test_wheel_spring_and_continuous_drag() {
            panel.animationActive=true
            wait(500)
            const list=findChild(panel,"lyricList"), row=findChild(panel,"lyricRow3")
            mouseWheel(panel,300,300,0,-120)
            verify(Math.abs(row.renderedY-row.targetY)>10,"Discrete wheel retains motion rather than snapping")
            wait(120)
            const midway=row.renderedY
            wait(120)
            verify(Math.abs(row.renderedY-midway)>1,"Wheel spring continues towards its target")
            panel.suspendFollow(true)
            list.contentY+=80
            wait(20)
            verify(Math.abs(row.renderedY-row.targetY)<.1,"Continuous drag follows the pointer directly")
        }
        function test_gap_timing_and_relayout() {
            const gaps=[100,400,800]
            for (let j=0;j<gaps.length;++j) {
                const lines=fixture()
                for (let i=0;i<lines.length;++i) lines[i].timeMs=i*gaps[j]
                panel.lyrics=lines
                panel.currentLineIndex=3
                panel.positionMs+=100
                wait(100)
                const k=panel.lineSpringStiffness
                if(j===0) compare(k,220)
                if(j===1) verify(k>170 && k<220)
                if(j===2) compare(k,170)
            }
            panel.fontSize=40
            panel.showTranslation=false
            wait(150)
            const row=findChild(panel,"lyricRow3"), list=findChild(panel,"lyricList")
            verify(Math.abs(row.y+row.height/2-list.contentY-list.height/2)<1,"Font/translation change keeps the active line aligned")
            panel.fontSize=28;panel.showTranslation=true
        }
        function test_touch_focus_and_dense_lines() {
            panel.suspendFollow(true)
            panel.currentLineIndex=6
            wait(100)
            compare(panel.focusLineIndex,3)
            compare(findChild(panel,"lyricRow4").blurAmount,0)
            panel.resumeFollow()
            wait(100)
            compare(panel.focusLineIndex,6)
            panel.positionMs+=200
            panel.currentLineIndex=8
            wait(50)
            compare(panel.seeking,false,"Skipping dense lines is not a user seek")
        }
        function test_focus_mask_handoff_and_hide() {
            panel.animationActive=true
            wait(500)
            const old=findChild(panel,"lyricRow3")
            panel.currentLineIndex=4
            wait(80)
            verify(old.focusAmount>0 && old.focusAmount<1,"Outgoing word mask fades instead of vanishing")
            wait(500)
            compare(old.focusAmount,0)
            verify(!findChild(panel,"lyricGrapheme3/1/0"),"Finished rows release emphasis quads")
            panel.animationActive=false
            wait(50)
            verify(!findChild(panel,"lyricGrapheme4/1/0"),"Hidden pages release emphasis quads")
        }
        function test_playhead_updates_do_not_rewind_words() {
            panel.animationActive = true
            panel.playing = true
            panel.positionMs = 12100
            panel.notifySeek()
            panel.positionMs = 12200
            panel.renderPositionMs = 12380
            panel.positionMs = 12300
            compare(panel.renderPositionMs, 12380, "A late decoder update cannot rewind the word mask")
            panel.advancePlayhead(16)
            verify(panel.renderPositionMs > 12380, "Small phase errors are corrected while moving forward")
            for (let i=0; i<100; ++i) panel.advancePlayhead(16)
            verify(panel.renderPositionMs <= panel.positionMs+250, "A stalled decoder cannot advance indefinitely")
            const held = panel.renderPositionMs
            panel.positionMs -= 100
            panel.advancePlayhead(16)
            verify(panel.renderPositionMs >= held, "The extrapolation cap must not pull a late frame backwards")
            panel.notifySeek()
            panel.positionMs -= 100
            compare(panel.renderPositionMs,panel.positionMs,"An explicit short backwards seek must be immediate")
            panel.playing = false
            compare(panel.renderPositionMs,panel.positionMs,"Pause aligns to media time")
        }
        function test_effect_layers_follow_actual_masks() {
            panel.animationActive = true
            panel.positionMs = 12200
            wait(550)
            const row = findChild(panel,"lyricRow3"), word = findChild(panel,"lyricWord3/0")
            verify(!row.layer.enabled,"The sharp current line has no redundant blur target")
            verify(word.layer.enabled || findChild(panel,"lyricAccent3/0/0"),"A partial word retains its gradient mask")
            panel.positionMs = 12420
            verify(!word.layer.enabled,"A completed word returns to native text")
            compare(word.opacity,1)
            panel.positionMs = 11900
            verify(!word.layer.enabled,"An unsung word needs no mask texture")
            compare(word.opacity,.4)
            panel.animationActive = false
            wait(30)
            verify(!findChild(panel,"lyricRow4").layer.enabled,"A suspended page releases blur even when still visible")
            panel.animationActive = true
            wait(30)
            verify(findChild(panel,"lyricRow4").layer.enabled,"The same blur returns on resume")
        }
        function test_spring_shared_driver_and_retarget() {
            function run(step) {
                springProbe.enabled = false
                springProbe.target = 0
                springProbe.enabled = true
                springProbe.retarget(100,170,2.2*Math.sqrt(170),.9)
                springProbe.pause()
                for (let t=step;t<240;t+=step) springProbe.setCurrentTime(t)
                springProbe.setCurrentTime(240)
                return springProbe.value
            }
            const sixty = run(16), highRefresh = run(8)
            verify(Math.abs(sixty-highRefresh)<.0001,"The spring trajectory is independent of frame sampling")
            const previous = springProbe.value
            springProbe.retarget(180,220,2.2*Math.sqrt(220),.9)
            compare(springProbe.value,previous,"Retargeting preserves the displayed position")
            springProbe.pause()
            springProbe.setCurrentTime(16)
            verify(springProbe.value>previous,"Retargeting retains forward velocity")
            springProbe.enabled = false
            compare(springProbe.value,180)
            compare(springProbe.running,false,"Suspending the page stops the animation driver")
        }
        function test_short_word_glow_and_release() {
            panel.animationActive = true
            panel.positionMs = 12300
            wait(550)
            const accent = findChild(panel,"lyricAccent3/0/0")
            verify(accent,"Short words get an accent without splitting every letter")
            verify(accent.glowAlpha>0 && accent.glowAlpha<.2,"Short-word glow stays subtle")
            verify(accent.scale>1 && accent.scale<1.02)
            const word=findChild(panel,"lyricWord3/0"), width=word.implicitWidth
            panel.positionMs=12550
            wait(20)
            verify(findChild(panel,"lyricAccent3/0/0"),"The glow has a short release after the word ends")
            panel.positionMs=12750
            wait(20)
            verify(!findChild(panel,"lyricAccent3/0/0"),"The finished accent releases its texture")
            verify(word.y < -panel.fontSize*.04,"A completed short word keeps its base float after the glow releases")
            panel.positionMs=13200
            wait(20)
            compare(word.y,-panel.fontSize*.05,"The base word float settles and holds instead of bouncing down")
            compare(word.implicitWidth,width,"Accent motion must not relayout the text")
            panel.positionMs=12300
            panel.reducedMotion=true
            wait(20)
            verify(!findChild(panel,"lyricAccent3/0/0"),"Reduced motion disables the accent")
        }
        function test_wrapped_lines_keep_alignment() {
            panel.width = 260
            panel.fontSize = 40
            const text = ["Quiet ","moon ","across ","the ","water"]
            panel.lyrics = [{text:text.join(""), timeMs:0, words:text.map((word,i)=>({text:word,startMs:i*400,endMs:(i+1)*400}))}]
            panel.currentLineIndex=0
            wait(150)
            const flow=findChild(panel,"lyricWordFlow0")
            let wrapped=false
            for (let i=0;i<flow.children.length;++i) {
                const word=flow.children[i]
                if (word.lineOffsetX===undefined || word.y===0) continue
                wrapped=true
                verify(word.lineOffsetX>0,"A shorter wrapped line must also be centered")
            }
            verify(wrapped,"The test must exercise a wrapped line")
            panel.alignmentMode="Left"
            wait(30)
            for(let i=0;i<flow.children.length;++i)
                if(flow.children[i].lineOffsetX!==undefined) compare(flow.children[i].lineOffsetX,0)
        }
        function test_spaces_do_not_steal_sweep_time() {
            const tokens=metrics.prepare([{text:"  glow   ",startMs:0,endMs:600},
                {text:" ",startMs:600,endMs:800}],fontProbe.font)
            compare(tokens[0].displayText,"glow")
            compare(tokens[0].glyphs.length,4,"Only visible graphemes belong to the sweep")
            verify(tokens[0].leadingSpace>0 && tokens[0].trailingSpace>tokens[0].leadingSpace)
            compare(tokens[1].charCount,0)
            verify(tokens[1].leadingSpace>0,"Whitespace still occupies layout space")
            panel.lyrics=[{text:"  glow    ",timeMs:0,words:[{text:"  glow   ",startMs:0,endMs:600},
                {text:" ",startMs:600,endMs:800}]}]
            panel.currentLineIndex=0
            panel.positionMs=300
            panel.animationActive=true
            wait(500)
            const word=findChild(panel,"lyricWord0/0"), accent=findChild(panel,"lyricAccent0/0/0")
            verify(word && accent)
            compare(word.text,"glow")
            verify(word.x>0 && word.parent.width>word.implicitWidth,"Keep both outside spaces in layout")
            compare(accent.sourceSize.x,word.implicitWidth,"The mask ends at the word, before trailing spaces")
            panel.positionMs=700
            wait(20)
            verify(!findChild(panel,"lyricAccent0/1/0"),"A pure space must never allocate an accent texture")
        }
        function test_only_last_visible_group_gets_terminal_emphasis() {
            const tokens=metrics.prepare([{text:"stay ",startMs:0,endMs:1600},
                {text:"now ",startMs:1600,endMs:3200},{text:"stay",startMs:3200,endMs:4800},
                {text:" ",startMs:4800,endMs:5100}],fontProbe.font)
            compare(tokens[0].emphasisDuration,1600,"An earlier repeated word is not the terminal group")
            compare(tokens[1].emphasisDuration,1600)
            compare(tokens[2].emphasisDuration,1920,"Trailing spaces do not take the terminal emphasis")
            verify(tokens[2].emphasisAmount>tokens[0].emphasisAmount)
            compare(tokens[3].emphasized,false)
        }
        function test_long_word_effect_window_and_handoff() {
            panel.animationActive=true
            panel.positionMs=11500
            wait(500)
            verify(!findChild(panel,"lyricGrapheme3/1/0"),"Future long words remain native text")
            panel.positionMs=12500
            wait(20)
            verify(findChild(panel,"lyricGrapheme3/1/0"),"Effects appear during the emphasis envelope")
            panel.positionMs=16719
            wait(20)
            const last=findChild(panel,"lyricGrapheme3/1/1"), word=findChild(panel,"lyricWord3/1")
            verify(last)
            verify(Math.abs(last.scale-1)<.0001)
            verify(Math.abs(last.y+last.padding-word.y)<.01,"The last quad settles before returning to native text")
            panel.positionMs=16800
            wait(20)
            verify(!findChild(panel,"lyricGrapheme3/1/0"))
            compare(word.opacity,1)
            compare(word.y,-panel.fontSize*.05)
        }
        function test_long_word_lift_is_independent_of_glow_padding() {
            panel.animationActive=true
            panel.positionMs=12300
            wait(500)
            const word=findChild(panel,"lyricWord3/1")
            compare(word.y,0,"An unsung long word must not float before its timestamp")
            verify(!findChild(panel,"lyricGrapheme3/1/0"),"No early emphasis texture is needed")
            for (const size of [28,56]) {
                panel.fontSize=size
                panel.positionMs=14200
                wait(50)
                const glyph=findChild(panel,"lyricGrapheme3/1/0")
                const shaped=findChild(panel,"lyricWord3/1")
                verify(glyph && glyph.scale>1.05)
                const center=glyph.mapToItem(shaped.parent,glyph.width/2,glyph.height/2)
                const displacement=center.y-(shaped.y+shaped.implicitHeight/2)
                verify(displacement<0,"Emphasis keeps its subtle upward offset")
                verify(displacement>-size*.031,"Scaling must not add a second lift through the padded quad's bottom edge")
            }
        }
        function test_brief_sustained_note_keeps_visible_expansion() {
            panel.lyrics=[{text:"better",timeMs:0,words:[{text:"better",startMs:0,endMs:1467}]}]
            panel.currentLineIndex=0
            panel.positionMs=880
            panel.animationActive=true
            wait(450)
            const glyph=findChild(panel,"lyricGrapheme0/0/0")
            verify(glyph && glyph.scale>1.055,"An eligible sub-two-second long note must visibly expand")
            verify(glyph.scale<1.1,"The short long-note accent remains bounded")
            verify(glyph.glowAlpha>.25,"A brief sustained note keeps a visible halo at its peak")
            verify(glyph.glowRadius>=panel.fontSize*.15,"Reducing energy must not collapse the halo to a hard edge")
            panel.reducedMotion=true
            wait(20)
            verify(!findChild(panel,"lyricGrapheme0/0/0"))
        }
        function test_incoming_line_clears_before_first_short_word() {
            panel.animationActive=true
            wait(500)
            const incoming=findChild(panel,"lyricRow4"), outgoing=findChild(panel,"lyricRow3")
            verify(incoming.blurAmount>.1)
            panel.positionMs=16000
            panel.currentLineIndex=4
            tryVerify(()=>incoming.blurAmount<.02,200,"The first short word must not spend its duration blurred")
            verify(outgoing.blurAmount>0 && outgoing.focusAmount>0,"The previous line still has a gradual handoff")
            wait(100)
            compare(incoming.blurAmount,0)
            verify(!incoming.layer.enabled,"The sharp row releases its blur target early")
        }
        function test_playback_rows_keep_their_stagger() {
            panel.animationActive=true
            wait(550)
            const outgoing=findChild(panel,"lyricRow3"), incoming=findChild(panel,"lyricRow4")
            const following=findChild(panel,"lyricRow5")
            const oldY=outgoing.renderedY, newY=incoming.renderedY, nextY=following.renderedY
            panel.seeking=false
            panel.currentLineIndex=4
            panel.scheduleLayout("geometry") // Font/delegate geometry can arrive in the same turn.
            wait(280)
            compare(panel.layoutReason,"playback","Coalesced layout must retain the playback intent")
            const a=oldY-outgoing.renderedY, b=newY-incoming.renderedY, c=nextY-following.renderedY
            verify(a>b+2,"The outgoing row must lead the incoming row")
            verify(b>c+2,"The following row must keep its own later start")
        }
    }
}
