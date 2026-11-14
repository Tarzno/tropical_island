import sys
src=open(sys.argv[0].replace('proc3.py','proc.py')).read()
src=src[:src.index("loop('waves_close_v1'")]
exec(src)
slice_events('flying_fox_v0','flying_fox',0.25,3.0,4,-8,thr_db=-10,post=0.3)
slice_events('flying_fox_v1','flying_fox_b',0.25,3.0,4,-8,thr_db=-10,post=0.3)
