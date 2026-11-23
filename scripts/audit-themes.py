#!/usr/bin/env python3
# Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

"""Check readability and chromatic separation in the bundled theme data."""
import itertools,json,math,re
from pathlib import Path
source=(Path(__file__).resolve().parents[1]/'Moth/Configuration.swift').read_text()
def linear(value):
    v=[int(value[i:i+2],16)/255 for i in (0,2,4)]
    return [q/12.92 if q<=.04045 else ((q+.055)/1.055)**2.4 for q in v]
def luminance(value):return sum(a*b for a,b in zip(linear(value),(.2126,.7152,.0722)))
def contrast(a,b):
    x,y=sorted([luminance(a),luminance(b)])
    return (y+.05)/(x+.05)
def lab(value):
    r,g,b=linear(value)
    l=(.4122214708*r+.5363325363*g+.0514459929*b)**(1/3)
    m=(.2119034982*r+.6806995451*g+.1073969566*b)**(1/3)
    s=(.0883024619*r+.2817188376*g+.6299787005*b)**(1/3)
    return (.2104542553*l+.793617785*m-.0040720468*s,1.9779984951*l-2.428592205*m+.4505937099*s,.0259040371*l+.7827717662*m-.808675766*s)
def distance(a,b):return math.dist(lab(a),lab(b))
constants={m[1]:re.findall(r'"([0-9A-F]{6})"',m[2]) for m in re.finditer(r'static let (\w+ANSI) = (\[[^\n]+\])',source)}
report=[]
for line in source.splitlines():
    match=re.search(r'Theme\(name:\s*"([^"]+)",\s*background:\s*0x([0-9A-F]+),\s*foreground:\s*0x([0-9A-F]+)',line)
    if not match:continue
    name,bg,fg=match.groups()
    if name=='system' or name.startswith('github-'):continue # adaptive alias and faithful upstream palettes
    raw=line.split('ansiColors:',1)[1].rstrip('),')
    colors=re.findall(r'"([0-9A-F]{6})"',raw) if raw.startswith('[') else constants[raw]
    chromatic=[colors[i] for i in [1,2,3,4,5,6,9,10,11,12,13,14]]
    normal_distance=min(distance(a,b) for a,b in itertools.combinations(colors[1:7],2))
    bright_distance=min(distance(a,b) for a,b in itertools.combinations(colors[9:15],2))
    result={'name':name,'background':bg,'foreground':fg,'foregroundContrast':round(contrast(bg,fg),2),'minimumANSITextContrast':round(min(contrast(bg,c) for c in chromatic),2),'normalMinimumOKLabDistance':round(normal_distance,3),'brightMinimumOKLabDistance':round(bright_distance,3),'ansi':colors}
    result['passed']=len(colors)==16 and len(set(colors))==16 and contrast(bg,fg)>=4.5 and min(contrast(bg,c) for c in chromatic)>=4.5 and min(normal_distance,bright_distance)>=.07
    report.append(result)
print(json.dumps(report,indent=2))
failed=[r['name'] for r in report if not r['passed']]
if failed:raise SystemExit('Theme audit failed: '+', '.join(failed))
