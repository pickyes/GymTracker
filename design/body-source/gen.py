import json, sys, numpy as np, cv2
from PIL import Image
import os
A_DIR=os.path.dirname(os.path.abspath(__file__))
S=5.6  # full-res px per canvas unit (1120/200)

def load(side):
    im=np.array(Image.open(f'{A_DIR}/Body{side.capitalize()}.png').convert('RGBA')).astype(int)
    R,G,B,A=im[...,0],im[...,1],im[...,2],im[...,3]
    alpha=A>128
    red=(alpha&(R>120)&(R-G>45)&(R-B>45)).astype(np.uint8)
    red=cv2.morphologyEx(red,cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
    n,lab,st,c=cv2.connectedComponentsWithStats(red,connectivity=4)
    return alpha,lab

def split_two(mask):
    o=cv2.morphologyEx(mask.astype(np.uint8),cv2.MORPH_OPEN,np.ones((7,7),np.uint8))
    n,l,st,c=cv2.connectedComponentsWithStats(o,connectivity=4)
    big=sorted([i for i in range(1,n) if st[i,4]>800],key=lambda i:c[i][1])[:2]
    # nearest-seed assignment so no original pixel is lost
    seeds=[(l==b) for b in big]
    dists=[cv2.distanceTransform((~s).astype(np.uint8),cv2.DIST_L2,5) for s in seeds]
    upper=mask&(dists[0]<=dists[1]); lower=mask&(dists[0]>dists[1])
    return upper,lower

FRONT={ # canvas-left = person's RIGHT on the front view
 'neck':[23,31,33,24,32,34],
 'trapRight':[38,43],'trapLeft':[40,44],
 'deltRight':[47,49],'deltLeft':[48,50],
 'pecRight':[52],'pecLeft':[51],
 'serratusRight':[57,71,67],'serratusLeft':[58,72,68],
 'bicepsRight':[59,62],'bicepsLeft':[60,61],
 'tricepsRight':[65],'tricepsLeft':[66],
 'abs':[69,70,74,76,90,91,101,102],
 'forearmRight':[81,87,89,92,94,99,105],'forearmLeft':[82,86,88,93,95,98,104],
 'handRight':[121,124,128,130,138,141,144],'handLeft':[123,125,129,131,139,145],
 'outerHipRight':[106],'outerHipLeft':[107],
 'hipFlexorRight':[111,114,117],'hipFlexorLeft':[112,113,118],
 'adductorRight':[120,134,155],'adductorLeft':[122,135,154],
 'quadRight':[109,126,133,165],'quadLeft':[110,127,132,166],
 'shinRight':[169,171,173,178],'shinLeft':[170,172,174,177],
 'calfRight':[175,179,181],'calfLeft':[176,180,182],
 'footRight':[191,193,195,207,211],'footLeft':[192,194,196,208,212],
}
BACK={ # canvas-left = person's LEFT on the back view
 'neck':[5,9,10,6],
 'trapLeft':[7],'trapRight':[8],
 'deltLeft':[15],'deltRight':[16],
 'rotatorCuffLeft':[17,19],'rotatorCuffRight':[18,20],
 'tricepsLeft':[22,24],'tricepsRight':[21,23],
 'forearmLeft':[27,32,34,35,37,45],'forearmRight':[28,31,33,36,38,44],
 'handLeft':[54,56,61],'handRight':[55,57,62],
 'latLeft':[25],'latRight':[26],
 'gluteLeft':[46,48],'gluteRight':[47,49],
 'outerHipLeft':[52],'outerHipRight':[53],
 'adductorLeft':[66,110],'adductorRight':[67,111],
 'hamstringLeft':[76,85,87,104,109],'hamstringRight':[77,86,88,105,108],
 'quadLeft':[89,106],'quadRight':[90,107],
 'calfLeft':[115,118,124,126,129],'calfRight':[116,119,125,127,128],
 'footLeft':[137],'footRight':[136],
}

def ellipse_mask(shape,cx,cy,rx,ry):
    m=np.zeros(shape,np.uint8); cv2.ellipse(m,(int(cx*S),int(cy*S)),(int(rx*S),int(ry*S)),0,0,360,1,-1); return m.astype(bool)

def build(side):
    alpha,lab=load(side)
    table=FRONT if side=='front' else BACK
    masks={k:np.isin(lab,v) for k,v in table.items()}
    if side=='front':
        for rid,pec,obl in ((53,'pecRight','obliqueRight'),(54,'pecLeft','obliqueLeft')):
            up,lo=split_two(lab==rid); masks[pec]|=up; masks[obl]=lo
    used=np.zeros_like(alpha)
    for m in masks.values(): used|=m
    unmapped=sorted({int(i) for i in np.unique(lab[(lab>0)&~used]) if (lab==i).sum()>400})
    # head: silhouette above the neck
    ys=np.where(masks['neck'])[0]; neck_top=ys.min()
    head=alpha.copy(); head[neck_top+8:]=False
    masks['head']=head&~used
    # neck: fill the silhouette between head and shoulders around the neck muscles
    ny0,ny1=neck_top, int(np.percentile(ys,95))
    band=np.zeros_like(alpha); band[ny0:ny1,560-75:560+75]=True
    masks['neck']|=(band&alpha&~used&~head)
    used=np.zeros_like(alpha)
    for m in masks.values(): used|=m
    free=alpha&~used
    # joints: the non-muscle body area around the joint, cut to the silhouette
    J=[('kneeRight' if side=='front' else 'kneeLeft',82,284 if side=='front' else 287,13,12),
       ('kneeLeft' if side=='front' else 'kneeRight',118,284 if side=='front' else 287,13,12),
       ('ankleRight' if side=='front' else 'ankleLeft',81,357,11,10),
       ('ankleLeft' if side=='front' else 'ankleRight',119,357,11,10),
       ('wristRight' if side=='front' else 'wristLeft',43,197,9,8),
       ('wristLeft' if side=='front' else 'wristRight',157,197,9,8)]
    for name,cx,cy,rx,ry in J:
        masks[name]=free&ellipse_mask(alpha.shape,cx,cy,rx,ry)
    used=np.zeros_like(alpha)
    for m in masks.values(): used|=m
    free=alpha&~used
    # hands / feet: the whole silhouette past the wrist / ankle joint
    L,Rn=('Right','Left') if side=='front' else ('Left','Right')
    H,W=alpha.shape
    yy,xx=np.mgrid[0:H,0:W]
    for nm,cond in ((f'hand{L}',(yy>203*S)&(yy<250*S)&(xx<56*S)),(f'hand{Rn}',(yy>203*S)&(yy<250*S)&(xx>144*S)),
                    (f'foot{L}',(yy>367*S)&(xx<100*S)),(f'foot{Rn}',(yy>367*S)&(xx>=100*S))):
        masks[nm]=masks.get(nm,np.zeros_like(alpha))|(free&cond)
    # elbows: the joint area between upper arm and forearm
    for nm,cx in ((f'elbow{L}',47),(f'elbow{Rn}',153)):
        masks[nm]=free&ellipse_mask(alpha.shape,cx,140,9,9)
    if side=='back':
        # lower back: the lumbar area between the lats and the glutes
        pts=np.column_stack(np.where(masks['latLeft']|masks['latRight']))
        lat_low=pts[pts[:,0]>pts[:,0].max()-120]
        g=np.column_stack(np.where(masks['gluteLeft']|masks['gluteRight']))
        g_top=g[g[:,0]<g[:,0].min()+40]
        hull=cv2.convexHull(np.vstack([lat_low,g_top])[:,::-1].astype(np.int32))
        m=np.zeros(alpha.shape,np.uint8); cv2.fillConvexPoly(m,hull,1)
        masks['lowerBack']=m.astype(bool)&alpha&~used
    return alpha,masks,unmapped

def polys(mask):
    m=cv2.morphologyEx(mask.astype(np.uint8),cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
    cs,_=cv2.findContours(m,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
    out=[]
    for c in cs:
        if cv2.contourArea(c)<120: continue
        a=cv2.approxPolyDP(c,1.0,True)[:,0,:]
        out.append([(round(x/S,1),round(y/S,1)) for x,y in a])
    return out

result={}
for side in ('front','back'):
    alpha,masks,unmapped=build(side)
    print(side,'unmapped regions >400px:',unmapped)
    cov=np.zeros_like(alpha)
    for m in masks.values(): cov|=m
    print(side,f'silhouette covered: {100*(cov&alpha).sum()/alpha.sum():.1f}%  overlaps: {sum(m.sum() for m in masks.values())-cov.sum()} px')
    result[side]={k:polys(v) for k,v in masks.items() if v.any()}
    np.save(f'{sys.argv[1]}/cov_{side}.npy',cov)
json.dump(result,open(f'{sys.argv[1]}/regions.json','w'))
print({s:sum(len(p) for v in result[s].values() for p in v) for s in result},'points')
