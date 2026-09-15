#!/usr/bin/env python3
# 1.1.5 story conversion gate: every number, dollar/percent figure, acronym and
# multi-word proper name in a 1.1.4 lesson (paragraphs, callouts, key terms,
# captions, quiz, takeaways) must appear in the converted beats.
# usage: story_fact_diff.py <dir with src/<course>.json (1.1.4) and out/<course>.json (1.1.5)> <course>...
import json,re,sys
S=sys.argv[1]; courses=sys.argv[2:]
NUM=re.compile(r"\$?\d[\d,]*(?:\.\d+)?%?")
NAME=re.compile(r"\b(?:[A-Z]{2,}[a-z]?s?|[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+)\b")
def block_text(b):
    t=b['type']
    if t=='paragraph': return [b['text']]
    if t=='callout': return [b['title'],b['text']]
    if t=='keyTerms': return [x['term']+': '+x['definition'] for x in b['terms']]
    if t=='diagram': return [b['caption']]
    if t=='chart': return [b['caption']]
    if t=='quiz': return [b['question'],b['explanation']]+b['choices']
    if t=='takeaways': return b['items']
    return []
def beat_text(b):
    v=b.get('visual') or {}
    parts=[b.get('heading',''),b.get('text','')]
    parts+= [t['term']+' '+t['definition'] for t in b.get('terms',[])]
    parts+= b.get('items',[])
    if b.get('check'): parts+= [b['check']['question'],b['check']['explanation']]+b['check']['choices']
    parts+= [str(v.get('value','')),str(v.get('label','')),' '.join(v.get('steps',[]))]
    for k in ('left','right'):
        if v.get(k): parts+=[v[k]['label'],v[k]['detail']]
    return ' '.join(parts)
norm=lambda s: s.replace('−','-').replace(',','')
total=0
for c in courses:
    src=json.load(open(f'{S}/src/{c}.json')); out=json.load(open(f'{S}/out/{c}.json'))
    newl={l['lessonID']:l for l in out['lessons']}
    for l in src['lessons']:
        old=' '.join(sum((block_text(b) for b in l['blocks']),[]))
        n=newl[l['lessonID']]
        new=norm(' '.join(beat_text(b) for b in n['beats'])+' '+n['summary'])
        miss_num=sorted({m for m in NUM.findall(old) if norm(m).rstrip('%') not in new})
        miss_name=sorted({m for m in NAME.findall(old) if m not in new and m not in ('The','A')})
        if miss_num or miss_name:
            total+=1
            print(f"{l['lessonID']}: numbers missing {miss_num} | names missing {miss_name}")
print('lessons with gaps:',total)
