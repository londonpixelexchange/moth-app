#!/usr/bin/env python3
# Copyright (c) 2026 T E Vaughan.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

"""Build private merged faces and a separately licensed icon fallback for Moth.
Requires fonttools[woff] and brotli. Original font outlines and layout tables stay intact.
"""
import argparse,copy,hashlib,json,zipfile
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.fontBuilder import FontBuilder


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def setname(font,identifier,value):
    font['name'].removeNames(nameID=identifier)
    for platform,encoding,language in [(3,1,0x409),(0,4,0)]: font['name'].setName(value,identifier,platform,encoding,language)
def variant(style):
    italic=style.endswith('Italic') or style=='Italic'
    weight=style.removesuffix('Italic') or 'Regular'
    return weight,italic

def names(font,style,variable=False):
    family='Wumpus Mono Pro Nerd Font Mono'+(' Variable' if variable else '')
    weight,italic=variant(style)
    substyle=('Italic' if weight=='Regular' else weight+' Italic') if italic else weight
    legacy=family if weight in ['Regular','Bold'] or variable else family+' '+weight
    legacy_style=('Bold Italic' if italic else 'Bold') if weight=='Bold' else ('Italic' if italic else 'Regular')
    ps='WumpusMonoProNFMVF' if variable else 'WumpusMonoProNFM-'+style
    for identifier,value in {1:legacy,2:legacy_style,3:'1.027;WumpusMonoPro;'+ps+';NF3.4.0-96',4:family+' '+substyle,5:'Version 1.027; Nerd Fonts 3.4.0-96; family build 1',6:ps,16:family,17:substyle}.items():setname(font,identifier,value)
    if variable:
        setname(font,25,'WumpusMonoProNFMVF')
        for instance in font['fvar'].instances:
            label=font['name'].getDebugName(instance.subfamilyNameID)
            instance.postscriptNameID=font['name'].addName('WumpusMonoProNFMVF-'+label.replace(' ',''),platforms=((3,1,0x409),))
        # Registered ital axes use 0 (roman) through 1 (italic). Normalized gvar
        # coordinates do not change, so the source designs are preserved exactly.
        axis=next(a for a in font['fvar'].axes if a.axisTag=='ital')
        factor=axis.maxValue
        if factor != 1:
            axis.minValue/=factor;axis.defaultValue/=factor;axis.maxValue=1
            for instance in font['fvar'].instances:instance.coordinates['ital']/=factor
            stat=font['STAT'].table
            ital_index=next(i for i,a in enumerate(stat.DesignAxisRecord.Axis) if a.AxisTag=='ital')
            for value in stat.AxisValueArray.AxisValue:
                if value.Format in [1,2,3] and value.AxisIndex==ital_index:
                    for field in ['Value','LinkedValue','NominalValue','RangeMinValue','RangeMaxValue']:
                        if hasattr(value,field):setattr(value,field,getattr(value,field)/factor)
                elif value.Format==4:
                    for record in value.AxisValueRecord:
                        if record.AxisIndex==ital_index:record.Value/=factor

def build(args):
    output=Path(args.output);app=Path(args.app_fonts)
    for folder in ['TTF','WOFF','WOFF2']: (output/folder).mkdir(parents=True,exist_ok=True)
    app.mkdir(parents=True,exist_ok=True)
    source=Path(args.source)
    donor=TTFont(args.icons,recalcTimestamp=False);base=TTFont(source/'WumpusMonoPro-Regular.ttf')
    additions={c:n for c,n in donor.getBestCmap().items() if c not in base.getBestCmap()}
    roots=set(additions.values())
    # FontForge flattened the supplied icon source; refuse implicit text dependencies.
    assert not any(donor['glyf'][n].isComposite() for n in roots)
    renamed={n:'nf_'+n for n in sorted(roots)}
    assert all(donor['hmtx'][n][0]==600 for n in roots)
    report={'sourceIcons':{'sha256':sha(args.icons),'version':donor['name'].getDebugName(5)},'fontToolsVersion':__import__('fontTools').__version__,'addedCodepoints':len(additions),'addedGlyphs':len(roots),'faces':[],'appFonts':[]}
    for path in sorted(source.glob('*.ttf')):
        original=TTFont(path);font=TTFont(path,recalcTimestamp=False);order=list(font.getGlyphOrder());original_order=list(order)
        if 'gvar' in font:font['gvar']  # Decompile before appending glyph IDs so new static entries are compiled.
        for name in sorted(roots):
            new=renamed[name];font['glyf'][new]=copy.deepcopy(donor['glyf'][name]);font['hmtx'][new]=donor['hmtx'][name];order.append(new)
        font.setGlyphOrder(order)
        for table in font['cmap'].tables:
            if table.isUnicode():
                table.cmap.update({c:renamed[n] for c,n in additions.items() if table.format in [12,13] or c<=0xFFFF})
        # Add UCS-4 mapping if the source only has BMP tables.
        if not any(t.format==12 and t.isUnicode() for t in font['cmap'].tables):
            from fontTools.ttLib.tables._c_m_a_p import CmapSubtable
            table=CmapSubtable.newSubtable(12);table.platformID=3;table.platEncID=10;table.language=0
            table.cmap={**original.getBestCmap(),**{c:renamed[n] for c,n in additions.items()}};font['cmap'].tables.append(table)
        variable='fvar' in font
        style='Regular' if variable else path.stem.split('-',1)[1]
        names(font,style,variable)
        font['post'].isFixedPitch=1;font['OS/2'].panose.bProportion=9
        for field in ['ascent','descent','lineGap']:setattr(font['hhea'],field,getattr(donor['hhea'],field))
        for field in ['sTypoAscender','sTypoDescender','sTypoLineGap','usWinAscent','usWinDescent']:setattr(font['OS/2'],field,getattr(donor['OS/2'],field))
        font['OS/2'].recalcUnicodeRanges(font)
        if 'DSIG' in font:del font['DSIG']
        filename='WumpusMonoProNerdFontMono-'+('Variable' if variable else style)
        file=output/'TTF'/(filename+'.ttf');font.save(file)
        entry={'source':path.name,'sourceSHA256':sha(path),'file':str(file.relative_to(output)),'sha256':sha(file),'glyphs':len(order),'originalGlyphs':len(original_order),'variable':variable}
        for format in ['woff','woff2']:
            web=TTFont(file,recalcTimestamp=False);web.flavor=format;web.save(output/format.upper()/(filename+'.'+format))
        report['faces'].append(entry)
        if not variable:
            # Moth embeds the proprietary text faces separately from OFL icons.
            face=TTFont(path,recalcTimestamp=False);weight,italic=variant(style)
            display='Wumpus Mono Pro '+(('Italic' if weight=='Regular' else weight+' Italic') if italic else weight)
            setname(face,4,display);face['post'].isFixedPitch=1;face['OS/2'].panose.bProportion=9
            for field in ['ascent','descent','lineGap']:setattr(face['hhea'],field,getattr(donor['hhea'],field))
            for field in ['sTypoAscender','sTypoDescender','sTypoLineGap','usWinAscent','usWinDescent']:setattr(face['OS/2'],field,getattr(donor['OS/2'],field))
            if 'DSIG' in face:del face['DSIG']
            app_path=app/path.name;face.save(app_path)
            report['appFonts'].append({'file':app_path.name,'sha256':sha(app_path)})
        print('Built',filename,flush=True)
    # New icon-only font: no Wumpus Mono Pro text or .notdef outlines are copied.
    from fontTools.pens.ttGlyphPen import TTGlyphPen
    empty=TTGlyphPen(None).glyph();glyphs={'.notdef':empty,'space':copy.deepcopy(empty)};metrics={'.notdef':(600,0),'space':(600,0)}
    for name in sorted(roots):glyphs[renamed[name]]=copy.deepcopy(donor['glyf'][name]);metrics[renamed[name]]=donor['hmtx'][name]
    fb=FontBuilder(1000,isTTF=True);fb.setupGlyphOrder(list(glyphs));fb.setupCharacterMap({32:'space',**{c:renamed[n] for c,n in additions.items()}})
    fb.setupGlyf(glyphs);fb.setupHorizontalMetrics(metrics);fb.setupHorizontalHeader(ascent=1100,descent=-300)
    fb.setupNameTable({'familyName':'Moth Nerd Symbols Mono','styleName':'Regular','uniqueFontIdentifier':'MothNerdSymbolsMono-3.4.0-96','fullName':'Moth Nerd Symbols Mono','psName':'MothNerdSymbolsMono-Regular','version':'Version 3.4.0-96; icon fallback 1','copyright':'Nerd Fonts icon contributors. See Nerd-Fonts-Licences for source notices.','licenseDescription':'Icon-only derivative. SIL Open Font License 1.1 and source icon notices are supplied separately.','licenseInfoURL':'https://github.com/ryanoasis/nerd-fonts/blob/v3.4.0/LICENSE'})
    fb.setupOS2(sTypoAscender=1100,sTypoDescender=-300,sTypoLineGap=0,usWinAscent=1100,usWinDescent=300);fb.setupPost(isFixedPitch=1)
    fb.font['head'].created=donor['head'].created;fb.font['head'].modified=donor['head'].modified;fb.font.recalcTimestamp=False
    symbols=app/'MothNerdSymbolsMono-Regular.ttf';fb.save(symbols)
    report['symbols']={'file':symbols.name,'sha256':sha(symbols),'codepoints':len(additions)+1}
    (output/'build-manifest.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--icons',required=True);p.add_argument('--output',required=True);p.add_argument('--app-fonts',required=True)
    build(p.parse_args())
