/// The words of the About screens (`ArtSource/design/Honest Chess.dc.html`'s
/// `PROMISES`), as plain records: the screens pick the colours.
library;

/// A promise tick's colour, in the design's repeating order.
enum PromiseTick { teal, blue, violet }

typedef Promise = ({String title, String body, PromiseTick tick});

const aboutStudioTitle = 'About Honest Arcade';

const aboutStudioLead =
    'Honest Arcade makes simple games and useful apps with no ads, no '
    "tracking, and no hidden agenda. Everything we build is open source, so "
    "you can see exactly what you're getting.";

const aboutStudioSecond =
    'Just good software that respects your time, privacy, and device.';

const supportKicker = 'SUPPORT HONEST ARCADE';

const supportText =
    "Our games stay free and ad-free because people chip in. If you'd like "
    'to help keep them that way, visit the website for details.';

/// The Support card's link line, without its →.
const supportLinkText = 'honestarcade.app/contribute';

const promisesKicker = 'OUR PROMISES';

/// The design's seven promises, "No accounts, no sign-in" reworded so it
/// stays true when Android's own backup copies the app's data.
const List<Promise> promises = [
  (
    title: 'No ads. Ever.',
    body:
        'No banners, no interstitials, no "watch a video to unlock". What '
        'you open is the whole thing.',
    tick: PromiseTick.teal,
  ),
  (
    title: 'No tracking, no analytics',
    body:
        'We collect nothing. No identifiers, no crash pings, no usage '
        'events.',
    tick: PromiseTick.blue,
  ),
  (
    title: 'No accounts, no sign-in',
    body:
        'Your progress is kept on your device, and this app never sends it '
        'anywhere.',
    tick: PromiseTick.violet,
  ),
  (
    title: 'No in-app purchases',
    body: 'Everything is included. Nothing is held back for money.',
    tick: PromiseTick.teal,
  ),
  (
    title: 'No permissions',
    body:
        'We ask for nothing — no contacts, no location, no storage, no '
        'network (unless explicitly needed for the app to function).',
    tick: PromiseTick.blue,
  ),
  (
    title: 'Open source',
    body:
        'The code is readable. Check how it works rather than taking our '
        'word for it.',
    tick: PromiseTick.violet,
  ),
  (
    title: 'Works offline, stays small',
    body:
        'No background activity, no battery drain while you are not using '
        'it (unless being online is explicitly needed for the app to '
        'function).',
    tick: PromiseTick.teal,
  ),
];

/// The chips under the promises.
const promiseChips = ['NO ADS', 'NO TRACKING', 'OPEN SOURCE'];

const siteLinkText = 'HONESTARCADE.APP';
const githubLinkText = 'SOURCE ON GITHUB';

typedef Feature = ({String title, String body});

const aboutAppTitle = 'About the App';

const appDescription =
    'Chess, complete and offline. The full rule set — castling, en passant, '
    'promotion, stalemate, the fifty-move draw — a computer opponent with '
    'five honest strength steps, and pass-and-play for two people on one '
    'phone. Nothing is unlocked with money, because there is nothing to '
    'buy.';

const featuresKicker = "WHAT'S IN IT";

/// The design's `FEATURES`, the first and last corrected to what was
/// built: threefold repetition is a draw too, and the statistics wording
/// stays true under Android's system backup.
const List<Feature> features = [
  (
    title: 'Every rule, no shortcuts',
    body:
        'Castling both sides, en passant, promotion to any piece, '
        'stalemate, threefold repetition, fifty-move and '
        'insufficient-material draws.',
  ),
  (
    title: 'Five strength steps',
    body:
        'Beginner to Master. The dial changes how deep it looks, and it says '
        'so.',
  ),
  (
    title: 'Pass-and-play for two',
    body: 'One phone, two clocks, an optional board rotation between turns.',
  ),
  (
    title: 'Clocks that behave',
    body: 'Untimed, blitz, rapid, classical or your own time and increment.',
  ),
  (
    title: 'Board you can live with',
    body: 'Four colour pairs, three piece styles, plain, felt or wood surface.',
  ),
  (
    title: 'Honest statistics',
    body:
        'Results by strength step and by time control. Kept on this phone; '
        'the app sends them nowhere.',
  ),
];

const appPromisesKicker = 'THE HONEST PROMISES';

/// About the App's seven chips: the design's `promiseChips` list.
/// [promiseChips], above, is About Honest Arcade's three.
const appPromiseChips = [
  'NO ADS',
  'NO TRACKING',
  'NO ACCOUNTS',
  'NO PURCHASES',
  'NO PERMISSIONS',
  'OPEN SOURCE',
  'WORKS OFFLINE',
];

const appPromisesButtonText = 'Honest Arcade Promises';

const madeByText = 'MADE BY';

/// The MADE BY links' text, without their ↗.
const arcadeLinkText = 'HONEST ARCADE';
