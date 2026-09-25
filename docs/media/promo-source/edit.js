// Textify promotional motion graphics. Higgsedit native API, v0.14.0.
// These are illustrative sample writing apps, not a live screen recording.
// Run from a directory containing textify-icon.png: higgsedit build edit.js
export default async ({ project, frame, text, rect, media, icon }) => {
  const p = await project({ dir: 'textify-promo', size: '1920x1080', fps: 30, background: '#091E37' });
  const logo = await p.add('../textify-icon.png');
  const C = { navy: '#091E37', ink: '#17334F', blue: '#1767DE', cyan: '#70E9DF', paper: '#F2F7FA', muted: '#657D92', line: '#DDE7EE', white: '#FFFFFF' };
  const T = (s,x,y,w,size=32,color=C.ink,weight=400,extra={}) => text(s,{x,y,width:w,height:size*2.6,fontFamily:'Inter',fontSize:size,fontWeight:weight,color,lineHeight:1.2,...extra});
  const R = (x,y,w,h,fill,radius=0,extra={}) => rect({x,y,width:w,height:h,fill,radius,...extra});
  const F = (name,x,y,w,h,children,extra={}) => frame({name,x,y,width:w,height:h,layout:'none',...extra},children);
  const enter = (delay=0,y=28) => ({enter:{at:delay,from:{y,opacity:0},duration:.6,easing:'house'}});
  const fade = (at,duration=.3) => [{property:'opacity',from:0,to:1,at,duration,easing:'ease-out'}];
  const mark = (x,y,s) => media({file:logo,x,y,width:s,height:s,fit:'contain',radius:s*.23});
  const shadow = {x:0,y:22,blur:50,color:'#06264120'};
  const line = (x,y,w,c=C.line) => R(x,y,w,2,c);
  const eyebrow = (s,x=130,y=104,color=C.blue) => T(s,x,y,1660,22,color,600,{letterSpacing:3});
  const progress = (i,dark=false) => [1,2,3,4,5,6].map((n)=>R(130+(n-1)*45,1008,30,3,n===i?(dark?C.cyan:C.blue):(dark?'#24415C':'#CCDBE5'),2));
  const brand = (dark=false) => F('Textify brand',1590,87,210,58,[mark(0,0,46),T('Textify',61,7,160,28,dark?C.white:C.ink,600)]);
  const disclosure = () => T('Animated macOS workflow · sample apps · illustrative timing',130,948,1660,21,C.muted,400);
  const bg = (dark=false) => [R(0,0,1920,1080,dark?C.navy:C.paper),R(1600,0,320,1080,dark?'#0E2946':'#EDF4F8')];
  const caret = (x,y,at=0,duration) => R(x,y,3,43,C.blue,1,{at,duration,animate:[{property:'opacity',keyframes:[{at:0,value:1,easing:'hold'},{at:.55,value:0,easing:'hold'},{at:1,value:1,easing:'hold'}]}]});

  function wave(x,y,w,h,duration,color=C.cyan) {
    return Array.from({length:34},(_,i)=> {
      const v=.22+.65*(.5+.5*Math.sin(i*1.89));
      return R(x+i*w/34,y,w/56,h,color,w/100,{duration,animate:[{property:'scaleY',keyframes:Array.from({length:Math.ceil(duration*8)+1},(_,j)=>({at:Math.min(j/8,duration),value:.18+v*(.5+.5*Math.sin(j*.9+i*.8)),easing:'smooth'}))}]});
    });
  }
  function recording(at,dur,processing=.7,target='Mail',targetIcon='mail') {
    return [F('Textify recording bar',698,805,524,108,[
      R(0,0,524,108,'#151B21',32,{strokeColor:'#507B99',strokeWidth:2,shadow}),
      icon(targetIcon,{x:24,y:25,size:33,color:'#D9E7F4'}),T(target,75,23,220,27,C.white,600),
      icon('audio-lines',{x:391,y:25,size:26,color:'#FA706C'}),
      T('Textify',429,26,90,20,'#8E989F',600),...wave(23,79,475,14,dur,'#88939C'),
    ],{at,duration:dur,motion:enter(0,14)}),
    F('Textify processing bar',698,805,524,108,[R(0,0,524,108,'#151B21',32,{strokeColor:'#507B99',strokeWidth:2,shadow}),icon(targetIcon,{x:24,y:25,size:33,color:'#D9E7F4'}),T(target,75,23,220,27,C.white,600),T('Transcribing…',23,72,430,20,'#A0ABB3',400)],{at:at+dur,duration:processing})];
  }
  function chrome(label,w,h) {
    return [R(0,0,w,h,C.white,24,{shadow}),R(0,0,w,70,'#F8FAFC',24),R(0,48,w,23,'#F8FAFC'),line(0,70,w),
      ...['#FC827C','#F4CC65','#6CCC9E'].map((c,i)=>R(28+i*28,28,13,13,c,7)),T(label,136,20,w-180,24,C.muted,600)];
  }
  function email(x,y,w,h,{resultAt=4.3,staticResult=false,compact=false}={}) {
    const k=w/1660;
    const items=[...chrome('Sample email · Draft',1660,550),
      R(0,71,232,479,'#F7FAFC',0),line(232,71,1),
      T('Mail',30,110,170,28,C.ink,600),R(18,167,196,54,'#E4EFFB',11),T('Drafts',42,181,158,23,C.blue,600),T('Inbox',42,251,158,23,C.muted),T('Sent',42,315,158,23,C.muted),
      T('To',286,111,80,24,C.muted),T('Maya',400,109,650,27,C.ink),line(282,162,1318),T('Subject',286,187,110,24,C.muted),T('Comments on the draft',400,183,1100,30,C.ink,600),line(282,240,1318),
      T('Draft saved locally',286,490,900,20,C.muted),R(1440,463,154,53,'#EBF1F6',11),T('Send',1475,476,100,22,'#90A1B0',600)];
    if(!staticResult) items.push(caret(285,301,0,resultAt));
    const result=[R(280,295,1120,115,'#EDF9F8',8,{duration:.55}),T('Hi Maya, I have added my comments\nto the draft.',285,301,1270,39,C.ink,400),caret(520,350,0)];
    items.push(F('Inserted email text',0,0,1660,550,result,{at:staticResult?0:resultAt}));
    return F('Email destination',x,y,w,h,[F('Email surface',0,0,1660,550,items,{animate:[{property:'scale',from:k,to:k,duration:.01}]})],{motion:enter(0,24)});
  }
  function document(x,y) {
    return F('Document destination',x,y,1660,550,[...chrome('Sample document · Project proposal',1660,550),
      R(0,71,210,479,'#F7FAFC'),T('Outline',30,110,160,22,C.muted,600),T('Overview',30,171,170,23,C.ink,600),T('Next steps',30,231,170,23,C.blue),
      T('A clearer next step.',282,111,1300,48,C.ink,600),T('A working proposal for the team',284,184,1220,25,C.muted),line(283,243,1260),
      caret(283,297,0,4.0),F('Inserted document text',0,0,1660,550,[R(278,290,1170,116,'#EDF9F8',8,{duration:.55}),T('The next step is to review the\nproposal together.',283,297,1280,42,C.ink),caret(674,350)],{at:4.0}),
      T('Private draft',283,481,900,20,C.muted),
    ],{motion:enter(0,24)});
  }
  function keycap(at,dur,label='Hold Right Command') {
    return F('Shortcut hint',1360,829,400,75,[R(0,0,400,75,'#E0ECEF',15),T(label,20,23,360,23,C.ink,600,{align:'center'})],{at,duration:dur,motion:enter(0,12)});
  }

  const scene = (nodes, options) => p.compose(F(options.name,0,0,1920,1080,nodes),options);

  // 01 / Opening. A cursor and writing contexts introduce the use case.
  scene([...bg(true),brand(true),eyebrow('VOICE → WRITING',130,177,C.cyan),
    F('Opening headline',130,279,1350,350,[T('Stay with',0,0,1320,126,C.white,600,{letterSpacing:-5}),T('your writing.',0,146,1320,126,C.white,600,{letterSpacing:-5}),R(855,160,7,119,C.cyan,2)],{motion:enter(.15,40)}),
    F('Opening subline',139,637,1350,60,[T('Speak naturally. Keep your place.',0,0,1350,35,'#AEC5D9')],{motion:enter(.8,20)}),
    ...[['mail','Emails'],['file-text','Documents'],['message-square','Messages']].map(([ic,label],i)=>F(label,140+i*390,803,345,91,[R(0,0,345,91,'#15314D',18,{strokeColor:'#294A65',strokeWidth:1}),icon(ic,{x:27,y:27,size:36,color:C.cyan}),T(label,87,29,240,27,C.white,400)],{motion:enter(1.15+i*.16,30)})),
    ...progress(1,true)],{at:0,dur:6,name:'01 Stay with your writing'});

  // 02 / Email. No destination text until the release/processing sequence ends.
  scene([...bg(),brand(),eyebrow('01 / AN EMAIL TO FINISH'),
    F('Email headline',130,147,1620,92,[T('Say it. Right where you write.',0,0,1600,70,C.ink,600,{letterSpacing:-2})],{motion:enter(0,18)}),
    email(130,254,1660,550),...recording(.1,3.5,.7),keycap(.15,3.45),keycap(3.6,.7,'Release to transcribe'),
    F('Inserted state',698,827,524,75,[R(0,0,524,75,'#D9F2E9',20),icon('check',{x:44,y:24,size:28,color:'#187556'}),T('Ready to edit',91,22,350,27,'#187556',600)],{at:4.3,duration:1.7,motion:enter(0,10)}),
    disclosure(),...progress(2)],{at:6,dur:6,name:'02 Dictate an email'});

  // 03 / Explain the shortcut with deliberate, coordinated emphasis.
  scene([...bg(true),brand(true),eyebrow('ONE SIMPLE FLOW',130,126,C.cyan),
    T('Hold. Speak. Release.',130,193,1680,86,C.white,600,{letterSpacing:-3,motion:{by:'word',from:{opacity:0,y:22},duration:.5,overlap:.45,easing:'house'}}),
    ...[
      ['keyboard','Hold','Your shortcut',.35],
      ['mic','Speak','Your own words',2.8],
      ['text-cursor-input','Release','Text at the cursor',5.2],
    ].map(([ic,title,sub,at],i)=>F(title+' step',130+i*565,370,530,382,[
      R(0,0,530,382,'#122F4C',24,{strokeColor:'#294B66',strokeWidth:1}),
      R(0,0,530,5,C.cyan,2,{at,duration:2.25}),
      T('0'+(i+1),36,30,130,24,'#85A5BF',600,{letterSpacing:2}),
      icon(ic,{x:38,y:108,size:61,color:C.cyan}),T(title,37,212,460,54,C.white,600),T(sub,40,302,450,28,'#ABC1D3'),
    ],{motion:enter(.15+i*.12,30)})),
    F('Flow result',130,812,1660,90,[R(0,0,1660,90,'#102B46',18),T('Your words arrive at the cursor, ready to edit.',32,25,1550,32,C.white)],{motion:enter(5.65,15)}),
    T('macOS default: Right Command · Enable the global trigger in Textify',130,950,1670,23,'#85A5BF'),...progress(3,true)],{at:12,dur:8,name:'03 Hold speak release'});

  // 04 / Document. Again, final output is inserted once after release.
  scene([...bg(),brand(),eyebrow('02 / A DOCUMENT TO SHAPE'),
    F('Document headline',130,147,1680,95,[T('Keep the thought moving.',0,0,1650,74,C.ink,600,{letterSpacing:-2})],{motion:enter(0,18)}),
    document(130,254),...recording(.1,3.2,.7,'Document','file-text'),keycap(.15,3.15),keycap(3.3,.7,'Release to transcribe'),
    F('Document inserted state',698,827,524,75,[R(0,0,524,75,'#D9F2E9',20),icon('check',{x:44,y:24,size:28,color:'#187556'}),T('Keep writing',91,22,350,27,'#187556',600)],{at:4.0,duration:2.0,motion:enter(0,10)}),
    disclosure(),...progress(4)],{at:20,dur:6,name:'04 Shape a document'});

  // 05 / On-device processing. Graphics illustrate architecture, not benchmarks.
  scene([...bg(true),brand(true),eyebrow('YOUR WORDS. YOUR COMPUTER.',130,140,C.cyan),
    F('Privacy headline',130,223,1620,215,[T('On-device',0,0,1600,103,C.white,600,{letterSpacing:-4}),T('speech recognition.',0,122,1650,103,C.white,600,{letterSpacing:-4})],{motion:enter(.15,30)}),
    F('Local processing diagram',1310,482,440,300,[
      R(0,0,440,258,'#15314D',25,{strokeColor:'#3C6581',strokeWidth:2}),R(169,258,103,22,'#3C6581',4),R(117,280,207,10,'#3C6581',4),
      mark(163,65,112),T('Processed locally',48,196,345,23,'#ABC1D3',600,{align:'center'})
    ],{motion:enter(.7,28)}),
    ...[['user-round','No account.'],['cloud-off','No speech upload.']].map(([ic,title],i)=>F(title,138,566+i*125,1050,95,[icon(ic,{x:0,y:15,size:43,color:C.cyan}),T(title,78,10,945,47,C.white,400)],{motion:enter(2+i*1.05,20)})),
    T('Offline dictation after a model is installed.',138,872,1590,31,'#ABC1D3',400,{animate:fade(5)}),...progress(5,true)],{at:26,dur:10,name:'05 On your device'});

  // 06 / Product and destination. Leave a readable final hold.
  scene([...bg(),
    F('End brand',691,148,600,151,[mark(0,0,140),T('Textify',184,24,530,86,C.ink,600,{letterSpacing:-3})],{motion:enter(.05,28)}),
    F('End promise',130,397,1660,220,[T('Your voice,',0,0,1660,98,C.ink,600,{align:'center',letterSpacing:-4}),T('in your writing.',0,116,1660,98,C.ink,600,{align:'center',letterSpacing:-4})],{motion:enter(.3,30)}),
    F('Call to action',645,710,630,87,[R(0,0,630,87,C.blue,19),T('Try the desktop preview',20,24,590,31,C.white,600,{align:'center'})],{motion:enter(.8,18)}),
    T('github.com/Player0109/Textify',320,842,1280,31,C.ink,400,{align:'center',animate:fade(1.1)}),
    T('macOS · Windows · Linux',320,934,1280,25,C.muted,600,{align:'center'}),
    T('GPU required · Linux uses Copy + paste · See download requirements',160,981,1600,20,C.muted,400,{align:'center'}),
  ],{at:36,dur:6,name:'06 Try Textify'});

  const fs = await import('node:fs/promises');
  await fs.mkdir('proof',{recursive:true});
  for(const t of [2.5,7.5,11.4,16,21.6,25.4,31,39]) await p.frame(t,`proof/frame-${t}.png`);
  // Render separately after reviewing proof frames: higgsedit render textify-promo ...
};
