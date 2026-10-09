"""Validate actual online decoding and report memory for each process separately."""
import argparse,json,pathlib,statistics

p=argparse.ArgumentParser(description=__doc__);p.add_argument('result',type=pathlib.Path)
a=p.parse_args();out=a.result
objects=json.loads((out/'objects.json').read_text(encoding='utf-8'))
samples=[json.loads(line) for line in (out/'samples.jsonl').read_text(encoding='utf-8').splitlines()]
summary=json.loads((out/'summary.json').read_text(encoding='utf-8'))
case=json.loads((out/'case.json').read_text(encoding='utf-8'))
errors=[];stages=[]
if not summary['finished'] or summary['exit']!=0:errors.append('Probe did not finish normally')
for step in case['steps']:
    error_start=len(errors)
    name=step['name'];rows=[r for r in samples if r['stage']==name]
    snapshots=[r for r in objects if r['stage']==name];end=next((r for r in reversed(snapshots) if r['label']=='end'),{})
    if not rows or not end:errors.append(name+': missing samples or end snapshot');continue
    tail=[r for r in rows if r['seconds']>=rows[-1]['seconds']-5]
    per_process={}
    for process_name in sorted({p['name'] for r in rows for p in r['processes']}):
        per_process[process_name]={k:round(statistics.median(sum(p[k] for p in r['processes'] if p['name']==process_name) for r in tail),2) for k in ('pws','ws','commit')}
    metrics=next(s for s in summary['stages'] if s['stage']==name)
    stage=dict(name=name,processes=per_process,pwsMiB=round(metrics['pws_median'],2),peakMiB=round(metrics['pws_peak'],2),
               commitMiB=round(metrics['commit_median'],2),gpuDedicatedMiB=metrics.get('gpu_dedicated_mib'),gpuSharedMiB=metrics.get('gpu_shared_mib'),
               playback=end.get('playback'),positionMs=end.get('positionMs'),trackId=end.get('trackId'),
               lyricLines=end.get('nativeLyricLines'),musicUrlSucceeded=end.get('musicUrlSucceeded'),musicUrlErrors=end.get('musicUrlErrors'),
               foregroundRatio=round(sum(r['ownForeground'] for r in rows)/len(rows),4),
               frameIntervalP95Ms=end.get('frameIntervalP95Ms'),mediaFormat=end.get('mediaFormat'),
               framesPerSecond=round(end.get('frameCount',0)/max(.001,end.get('stageMs',0)/1000),2),queueCount=end.get('queueCount'))
    if any(r.get('sessionLocked') is not False for r in rows):errors.append(name+': session locked')
    if case.get('foreground') and not step.get('ignoreForeground') and stage['foregroundRatio']<.98:errors.append(name+': foreground lost')
    active=any(s['id']==end.get('activeSource') and s['hostReady'] for s in end.get('sources',[]))
    if step.get('action') in ('source','importSource') and not active:errors.append(name+': source did not load')
    if step.get('requirePlaying') or step.get('action')=='playResult':
        progressing=[r['positionMs'] for r in snapshots if r.get('playback')=='Playing']
        if not active or end.get('playback')!='Playing' or len(progressing)<2 or progressing[-1]-progressing[0]<1000 or not end.get('musicUrlSucceeded'):
            errors.append(name+': no confirmed plugin + advancing online decoder')
        if not end.get('trackSource') or end.get('trackPath'):errors.append(name+': workload is not an online source track')
        if end.get('playbackError'):errors.append(name+': playback error')
    if step.get('requireLyrics') and step.get('action')!='playResult' and stage['framesPerSecond']<30:
        errors.append(name+': lyric animation did not submit continuously')
    if step.get('requireLyrics') and not end.get('nativeLyricLines'):errors.append(name+': empty lyrics')
    if step.get('requireStopped') and end.get('playback')=='Playing':errors.append(name+': playback did not stop')
    if step.get('requireVideo'):
        if not end.get('videoReady') or end.get('videoError'):errors.append(name+': video is not ready')
        if (end.get('videoWidth'),end.get('videoHeight'))!=tuple(step.get('videoSize',[1920,1080])):
            errors.append(name+': actual decoded video size differs')
        video_times=[r.get('videoFrameTimeMs',-1) for r in snapshots]
        if len(video_times)<2 or video_times[-1]-video_times[0]<1000:errors.append(name+': video frames did not advance')
        if end.get('nativeVideo') and max(r.get('videoQueuedFrames',0) for r in snapshots)>3:
            errors.append(name+': native video queue exceeded bound')
        stage.update(videoWidth=end.get('videoWidth'),videoHeight=end.get('videoHeight'),
                     nativeVideo=end.get('nativeVideo',False),videoPresentedFrames=end.get('videoPresentedFrames'))
    stage['valid']=len(errors)==error_start
    stages.append(stage)
result=dict(valid=not errors,errors=errors,stages=stages)
(out/'online-summary.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(result,indent=2,ensure_ascii=True))
raise SystemExit(bool(errors))
