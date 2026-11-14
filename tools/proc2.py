import sys
sys.argv=[sys.argv[0],sys.argv[1],sys.argv[2]]
src=open(sys.argv[0].replace('proc2.py','proc.py')).read()
src=src[:src.index("loop('waves_close_v1'")]
exec(src)
loop('night_insects_v0','night_insects',5,-22)
loop('night_frogs_v0','night_frogs',5,-23)
loop('brush_v1','brush',2,-20)
