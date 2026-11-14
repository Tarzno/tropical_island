import sys, numpy as np, wave, glob, os
def readwav(p):
    import subprocess
    raw=subprocess.run(['ffmpeg','-loglevel','error','-i',p,'-f','f32le','-ac','2','-ar','48000','-'],capture_output=True).stdout
    return np.frombuffer(raw,dtype=np.float32).reshape(-1,2)
for p in sorted(glob.glob(sys.argv[1]+'/*.wav')):
    a=readwav(p); m=a.mean(1); sr=48000
    win=sr//2
    rms=[20*np.log10(np.sqrt((m[i:i+win]**2).mean())+1e-9) for i in range(0,len(m)-win,win)]
    # spectral centroid
    sp=np.abs(np.fft.rfft(m[:sr*8]*np.hanning(min(len(m),sr*8))))
    fr=np.fft.rfftfreq(min(len(m),sr*8),1/sr)
    cen=(sp*fr).sum()/sp.sum()
    # tonality: peakiness
    peak=np.sort(sp)[-50:].mean()/sp.mean()
    print(os.path.basename(p), f"{len(m)/sr:.1f}s centroid={cen:.0f}Hz peaky={peak:.0f}", ' '.join(f"{int(r)}" for r in rms))
