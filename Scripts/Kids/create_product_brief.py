from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, Color, white
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/pdf/kidsjellyfin-executive-brief.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)
W, H = 612, 792
INK, TEAL, MUTED, PAPER = map(HexColor, ['#132D3B', '#007D79', '#506472', '#F5F4EF'])
c = canvas.Canvas(str(OUT), pagesize=(W, H), pageCompression=1)
c.setTitle('KidsJellyFin - A seven-page proposal for the Senior Fatherhood Executive')
c.setAuthor('KidsJellyFin product and engineering')
styles = {}
for name, size, leading, color, font in [('body', 11.5, 16, INK, 'Helvetica'), ('small', 9.5, 13, MUTED, 'Helvetica'), ('white', 11.5, 16, white, 'Helvetica'), ('label', 10, 13, TEAL, 'Helvetica-Bold'), ('head', 17, 21, INK, 'Helvetica-Bold')]:
    styles[name] = ParagraphStyle(name, fontName=font, fontSize=size, leading=leading, textColor=color, spaceAfter=0)

def text(s, x, top, width=516, style='body'):
    p = Paragraph(s, styles[style]); _, h = p.wrap(width, H)
    assert top-h >= 55, (s, top, h)
    p.drawOn(c, x, top-h)
    return top-h

def line(y):
    c.setStrokeColor(HexColor('#D8DDD9')); c.setLineWidth(.7); c.line(48,y,564,y)

def page(n, kicker, title, subtitle):
    c.setFillColor(PAPER); c.rect(0,0,W,H,fill=1,stroke=0)
    c.setFillColor(TEAL); c.setFont('Helvetica-Bold',9); c.drawString(48,752,'KIDSJELLYFIN  /  FAMILY PRODUCT REVIEW')
    c.setFillColor(MUTED); c.setFont('Helvetica',9); c.drawRightString(564,752,'05 OCT 2026')
    text(kicker,48,715,style='label')
    c.setFillColor(INK); c.setFont('Helvetica-Bold',29); c.drawString(48,661,title)
    text(subtitle,48,638,style='body')
    line(57); c.setFillColor(MUTED); c.setFont('Helvetica',8.5)
    c.drawString(48,39,'SFE REVIEW  /  INTENDED EXPERIENCE + VERIFIED STATUS')
    c.drawRightString(564,39,f'{n:02} / 07')

def section(label, body, y, width=516, x=48):
    y=text(label,x,y,width,'head')-8
    return text(body,x,y,width)-22

def box(x,y,w,h,title,body,dark=False):
    c.setFillColor(INK if dark else white); c.roundRect(x,y,w,h,12,fill=1,stroke=0)
    st='white' if dark else 'body'
    text(f'<b>{title}</b>',x+16,y+h-17,w-32,st)
    text(body,x+16,y+h-49,w-32,st)

def row(y,label,body):
    text(label,48,y,135,'label')
    low=text(body,200,y,364,'body')
    line(low-12)
    return low-27

page(1,'01 / THE PITCH','More radio. Less iTunes.','For the Senior Fatherhood Executive: give a child a remote they can succeed with, and a parent a catalog they can trust.')
box(48,405,516,155,'Their shows. Their remote. Your peace of mind.','A familiar picture gets them to a show. Two large actions do the rest: <b>Next</b> continues its story; <b>Shuffle</b> finds something fresh within that show. Movies have one clear Play or Resume action.',True)
y=375
y=section('The job we are hiring it to do','Let a child who cannot read start something familiar without a parent operating the TV. Reduce decisions, preserve context, and make stopping as easy as starting.',y)
box(48,185,248,92,'Child value','Recognize a picture. Pick an action. Enjoy the show.')
box(312,185,252,92,'Parent value','Only Kid TV and Kid Movies. Advanced controls behind a gate.')
text('<b>The executive ask:</b> approve this small, focused experience for a physical Apple TV and family pilot. Simulator engineering evidence is strong; everyday household reliability still needs that pilot.',48,152)
c.showPage()

page(2,'02 / COMPLETE NAVIGATION','Pictures lead the way.','A stable two-category home, shallow title screens, and an ordinary Apple TV remote. Text supports the pictures; it is never the only cue.')
box(48,484,248,93,'SHOWS  [default home]','Four artwork cards per row. Focus stays visible. Select a familiar show.')
box(312,484,252,93,'MOVIES','Same grid and controls. Select a familiar film.')
box(48,355,248,106,'SHOW TITLE','Large recognizable artwork.<br/><b>Next / Again</b> and <b>Shuffle</b>. No season wall.')
box(312,355,252,106,'MOVIE TITLE','Artwork and progress.<br/>One <b>Play / Resume / Play again</b> action.')
box(48,255,516,87,'PLAYER','Remote Play/Pause. Select opens controls. A paused, focused timeline supports seeking. Back dismisses controls, then returns to the title.')
y=228
y=row(y,'AFTER PLAYBACK','Shows: next picture, countdown and focused Stop; then the next approved episode or a clear ending. Movies: return without autoplay.')
y=row(y,'PARENTS','Small entry on home and player. Masked PIN opens episode selection, session settings, accessibility, tracks and connection help.')
text('<b>Every return restores context:</b> category, scroll position and prior card focus. Loading, empty categories and errors keep a route Back or to protected help. No search, mixed shelves, trailers or adult catalog.',48,y,style='small')
c.showPage()

page(3,'03 / PLAYBACK CONTRACT','Two buttons. Clear rules.','Ordered progress and Shuffle freshness are separate promises. A failed connection must not silently spend either one.')
y=581
y=row(y,'NEXT / AGAIN','Next starts the ordered episode, or resumes its checkpoint. Advance only on natural completion. Finale offers Again. A missing successor needs parent review, not a silent jump.')
y=row(y,'SHUFFLE','Draw from this show only. Consume the draw after playback is proven. Avoid repeats until the bag is exhausted and avoid an immediate repeat at refill. A new Shuffle choice draws fresh; interrupted playback can Resume.')
y=row(y,'EPISODE RULES','Use verified regular episodes with unambiguous positive season/episode numbering. Exclude extras and specials. Ambiguous queues stay blocked for parent review; do not rename or alter server media.')
y=row(y,'SESSION BUDGET','Default: two episodes. Parents can choose one, two or continuous. Count each genuine completion once. A ten-second visual countdown gives a focused Stop action. Relaunch preserves the interrupted session budget.')
y=row(y,'MOVIES','One primary action. Resume remembers position; completion becomes Play again. Start over is parent-only. A movie does not launch another movie.')
text('<b>Intentional limit:</b> this is a convenient stopping point, not a daily screen-time lock. The app cannot control other Apple TV apps or system navigation. Initial scope excludes cross-show radio, profiles, downloads and Live TV.',48,y,style='small')
c.showPage()

page(4,'04 / PARENT CONTROL AND TRUST','The gate hides complexity.','Server authorization determines what exists. Unlocking Parents adds controls within the same kids catalog; it never unlocks adult libraries.')
y=581
y=section('Parents get a toolbox, not another media wall','Choose a show, season and episode using thumbnails. <b>Play once</b> leaves the ordered cursor alone; <b>Set Next here</b> deliberately moves it. Confirm progress resets. Configure episode count, speech, captions/audio, PIN and connection help. Relock on exit, background and inactivity.',y)
y=section('Two independent content boundaries','Use a restricted Jellyfin account with exactly the approved Kid TV and Kid Movies library IDs. The app verifies server, user and library binding; validates item kind and ancestry; and reauthorizes the selected item before every Play. Old-account art and catalogs cannot carry across identity changes.',y)
box(48,178,516,140,'NON-NEGOTIABLE: MEDIA STAYS UNTOUCHED','Only the audited Plex catalog is eligible. No drive-wide discovery, file conversion, rename, delete, permission changes or sidecars on the RAID. The client stores its own progress and sends ordinary playback reports; it never edits media.',True)
text('<b>Curation remains in Jellyfin.</b> Parents manage approved library additions through the established server workflow. The child app contains no server-admin credential. A parent PIN controls UI complexity; it is separate from the Jellyfin password.',48,150)
c.showPage()

page(5,'05 / RELIABILITY AND ACCESSIBILITY','Useful when life interrupts.','A power cut, a network drop or a child pressing Back should produce a predictable recovery, not a mystery or a new stream.')
y=581
y=row(y,'PROGRESS','Client SwiftData saves positions every ten seconds and at pause, seek, background, stop and completion. Private CloudKit mirroring is configured for the same Apple account and verified Jellyfin identity. Secrets and media never sync.')
y=row(y,'SYNC LIMIT','Local saves work offline. Delivery across devices is eventual, not an instant handoff or playback lock. Automated two-store merge tests pass; live signed-device CloudKit delivery remains a separate acceptance gate.')
y=row(y,'FAILURES','No autoplay after app relaunch. Bounded startup/buffering recovery retries the exact item. Token denial requires parent action. Cancel stale work and keep one playback owner. Damaged progress gets explicit recovery, not silent replacement.')
y=row(y,'NON-READERS','Large familiar artwork, stable action positions, clear focus and paired icon/label cues. Respect reduced motion. Optional settled-focus speech avoids stale or duplicate VoiceOver narration. Test reading, motor and hearing needs separately.')
y=row(y,'SERVER','Log cleanup is verified. The login service remains the fallback. Unattended boot, daemon storage access and post-reboot recovery still require the staged administrator diagnostic and observed reboot validation.')
text('<b>Make every wait visible.</b> Show verified artwork as it becomes ready; distinguish loading from an empty library. Keep parents reachable during errors. No raw credentials, diagnostic URLs or technical server messages in child-facing screens.',48,y,style='small')
c.showPage()

page(6,'06 / ENGINEERING EVIDENCE','Ready for the next test.','Implemented, observed and still unverified are different states. The simulator is useful evidence; the living-room Apple TV is the release test.')
y=581
y=row(y,'PROVEN NOW','Native core and persistence: 92 tests pass. Restricted-account TV/movie playback, pause, seek, resume, real EOF and session-cap behaviors have simulator evidence. Denied-library probes and exact scoped-state restoration are recorded.')
y=row(y,'LATEST TRIAL','Seven launches: first approved Shows batch median 1.45 s; first browse 1.49 s. Full catalog completes at 3.68 s. Eight real starts and eight native teardowns succeed; teardown median 61 ms. No new playback speedup claim.')
y=row(y,'PERF LIMITS','Latest TV output median 1.87 s (n=3); movie output 2.34 s (n=4). Grid art: 204 ms (n=128). These warm H264 simulator samples are not physical-device results, RAID seek measurements or broad codec coverage.')
y=row(y,'OPEN CLIENT WORK','Cold title/episode loading, inherited Swift 6 modernization and broader format recovery. One approved S1E0 queue needs a parent numbering decision. AVI/MPEG4 playback needs exact-item render proof. All 16 current remote navigation checks pass.')
y=row(y,'OPEN EXTERNAL PROOF','Physical Apple TV playback and accessibility, two signed clients for iCloud, family observation and server boot resilience. Workflow publication needs GitHub permission; ordinary app-code pushes are separate and available.')
text('Evidence: repository <b>docs/kids-validation.md</b>, <b>docs/kids-icloud.md</b>, and <b>docs/kids-performance-optimization.md</b>; trial aggregates opt07-opt10. Failed experiments are retained and excluded from final acceptance. Status as of 05 Oct 2026.',48,y,style='small')
c.showPage()

page(7,'07 / THE FAMILY BOARD DECISION','Approve a small, real pilot.','The product succeeds when a child can use it and the household can rely on it. Fewer controls are a hypothesis we can test together.')
y=581
y=section('Approve the defaults','Shows first. Next and within-show Shuffle. Two episodes per session. Again after an ordered finale. A shared household progress identity. Specific episode selection and resets behind the parent gate. No growth into a general media browser.',y)
y=section('Run the pilot in three steps','<b>1. Device gate:</b> build and sign for the family Apple TV; prove ten representative starts across real formats, sound, seeking and sleep/wake. Target warm-LAN median first frame at or below three seconds.<br/><br/><b>2. Household gate:</b> after one demonstration, observe five attempts to find/start/stop/switch/return. Target at least four unassisted starts. Record focus mistakes, stalls and parent rescues.<br/><br/><b>3. Resilience gate:</b> observe reboot recovery, offline/reconnect and cloud handoff/reset on signed devices. Keep a recoverable client build and server fallback.',y)
box(48,132,516,101,'RELEASE RULE','Any forbidden-content leak blocks release. Do not sunset Plex until client streaming and server recovery are observed reliably. Simulator passes, a configured cloud container or a connected server do not replace those gates.',True)
text('<b>What you are buying:</b> a quiet, legible living-room routine. Judge the app by successful child choices and reliable playback, not the number of features we can fit on the screen.',48,111,style='small')
c.showPage(); c.save()
print(OUT)
