import sys,time,tempfile,json,os,argparse
from pathlib import Path
sys.path.insert(0,str(Path('apps/greeter/companion').absolute()))
import resources,handoff,cover
from unittest.mock import patch
parser=argparse.ArgumentParser();parser.add_argument('--baseline',action='store_true');args=parser.parse_args()
verify=args.baseline
root=Path('/usr/local/lib/kos-greeter/app/public-display')
count=0
original=resources.image_copy
def measured(*a,**k):
 global count
 count+=1
 return original(*a,**k)
rows=[]
resources._CANONICAL_DIMENSIONS.clear()
if args.baseline:
 def uncached(data,digest,avatar=False):
  clean,size=resources.image_copy(data,avatar)
  if clean!=data:raise ValueError('noncanonical')
  return size
 resources.canonical_dimensions=uncached
with tempfile.TemporaryDirectory() as temp,patch.object(resources,'image_copy',side_effect=measured):
 r=handoff.Runtime(temp)
 for name,fn in [('build',lambda:handoff.build(r.session,r.uid,root,0,verify_resources=verify)),]:
  old=count;t=time.perf_counter();desc=fn();assert desc['resource']['version']!='default','No live publication; do not report a default-only profile';rows.append((name,time.perf_counter()-t,count-old))
 for name,fn in [('write',lambda:r.write(desc,root,0,verify_resources=verify)),('consume',lambda:r.consume(root,0,remove=False,verify_resources=verify)),('read_reference',lambda:handoff.read_reference(temp,r.session,r.digest.hex(),root,0)),('cover_resource_state',lambda:cover.resource_state(desc,root,0))]:
  old=count;t=time.perf_counter();fn();rows.append((name,time.perf_counter()-t,count-old))
 r.close()
print(json.dumps({'published_resource_only':True,'baseline_reencode_policy':args.baseline,'canonical_calls':count,'stages':rows},indent=2))
