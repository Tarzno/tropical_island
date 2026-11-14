import numpy as np, subprocess, os, sys
SR=48000
SRC=sys.argv[1]; DST=sys.argv[2]
os.makedirs(DST,exist_ok=True)
def read(name):
    raw=subprocess.run(['ffmpeg','-loglevel','error','-i',f'{SRC}/{name}_00001.flac','-f','f32le','-ac','2','-ar',str(SR),'-'],capture_output=True).stdout
    return np.frombuffer(raw,dtype=np.float32).reshape(-1,2).copy()
def write(a,out,mono=False):
    if mono: a=a.mean(1,keepdims=True)
    ch=a.shape[1]
    p=subprocess.run(['ffmpeg','-loglevel','error','-y','-f','f32le','-ac',str(ch),'-ar',str(SR),'-i','-','-c:a','pcm_s16le',f'{DST}/{out}.wav'],input=a.astype(np.float32).tobytes())
def trim_tail(a):
    m=np.abs(a).max(1)
    idx=np.where(m>1e-3)[0]
    return a[:idx[-1]+1] if len(idx) else a
def norm(a,db):
    rms=np.sqrt((a**2).mean())
    return a*(10**(db/20)/max(rms,1e-9))
def loop(name,out,xf=4.0,db=-20,mono=False,hp=None):
    a=trim_tail(read(name))
    a=a[int(0.3*SR):]  # skip possible start transient
    X=int(xf*SR); L=len(a)
    t=np.linspace(0,np.pi/2,X)[:,None]
    o=a[:L-X].copy()
    o[:X]=a[:X]*np.sin(t)+a[L-X:]*np.cos(t)
    write(norm(o,db),out,mono)
    print(out,len(o)/SR)
def env(a,win):
    m=a.mean(1); n=len(m)//win
    return np.sqrt((m[:n*win].reshape(n,win)**2).mean(1))
def slice_events(name,prefix,minlen,maxlen,count,db,mono=True,pre=0.03,post=0.25,thr_db=-14,start=0.0):
    a=trim_tail(read(name)); a=a[int(start*SR):]
    win=int(0.01*SR)
    e=env(a,win); edb=20*np.log10(e+1e-9)
    thr=np.percentile(edb,98)+thr_db
    on=edb>thr
    segs=[];i=0
    while i<len(on):
        if on[i]:
            j=i
            gap=0
            while j<len(on) and gap<12:
                gap = gap+1 if not on[j] else 0
                j+=1
            segs.append((i,j-gap)); i=j
        else: i+=1
    res=[]
    for s,e2 in segs:
        L=(e2-s)*0.01
        if minlen<=L<=maxlen:
            pk=edb[s:e2].max()
            res.append((pk,s,e2))
    res.sort(reverse=True)
    res=res[:count]
    res.sort(key=lambda r:r[1])
    for k,(pk,s,e2) in enumerate(res):
        a0=max(0,int((s*0.01-pre)*SR)); a1=min(len(a),int((e2*0.01+post)*SR))
        seg=a[a0:a1].copy()
        f=np.ones(len(seg)); fi=int(0.005*SR); fo=int(min(post,0.2)*SR)
        f[:fi]=np.linspace(0,1,fi); f[-fo:]=np.linspace(1,0,fo)**2
        seg*=f[:,None]
        pk_lin=np.abs(seg).max()
        seg=seg/pk_lin*(10**(db/20))
        write(seg,f'{prefix}_{k}',mono)
    print(prefix,len(res),[round((r[2]-r[1])*0.01,2) for r in res])

loop('colony_v0','colony_a',4,-20)
loop('colony_v1','colony_b',4,-20)
loop('tortoise_v0','tortoise_munch',2,-24,mono=True)
slice_events('noddy_v0','noddy',0.1,1.6,8,-6,thr_db=-10)
slice_events('colony_v1','colony_call',0.1,1.2,8,-6,thr_db=-6)
