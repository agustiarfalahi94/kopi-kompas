import 'data/brew_schema.dart' show FieldGroup;

/// Every user-facing string in the app, in English and Bahasa Indonesia.
///
/// Static getters rather than a map lookup, so a string that does not exist
/// fails to compile instead of rendering as an empty box. [all] exists only
/// for the test that checks nothing was copied across untranslated.
///
/// [language] is set at startup from the stored preference, and again when
/// the switch in Settings is used.
class AppStrings {
  const AppStrings._();

  static String language = 'en';

  static bool get _id => language == 'id';

  static String _s(String en, String id) => _id ? id : en;

  static String get appName => 'Kopi Kompas';
  static String get newEntryTitle => _s('What did you brew?', 'Bikin apa?');
  static String get describeHint => _s(
    'e.g. 18g in, 36g out in 28 seconds, wdt and tamp, honduras medium',
    'mis. 18g masuk, 36g keluar dalam 28 detik, wdt dan tamping, honduras',
  );
  static String get parseButton => _s('Continue', 'Lanjut');
  static String get parsing => _s('Reading your brew…', 'Membaca seduhan…');
  static String get scoring => _s('Scoring…', 'Menilai…');
  static String get saveButton => _s('Save', 'Simpan');
  static String get noChanges => _s('Nothing changed', 'Nggak ada yang diubah');
  static String get doneButton => _s('Done', 'Selesai');
  static String get emptyLog =>
      _s('No brews yet. Tap + to log one.', 'Belum ada. Ketuk + untuk mulai.');
  static String get notScored => _s('Not scored', 'Tidak dinilai');

  /// A status, not an instruction. It used to read "tap to retry" and was
  /// rendered in three places that had no tap handler between them; the
  /// action now lives in a real button, and the full log — an archive with
  /// no honest tap target — simply reports the state.
  static String get scoreFailed => _s('Not scored yet', 'Belum dinilai');

  /// Why a score failed, when the reason is the Worker rather than the phone.
  ///
  /// The parse step has said "no connection" and "daily limit reached" since
  /// it shipped; the score step discarded the kind and said nothing at all,
  /// so an overloaded Gemini read exactly like being offline.
  static String get scoreUnavailable => _s(
    'The scorer is busy. Your brew is saved — try again in a minute.',
    'Penilai sedang sibuk. Seduhan kamu aman — coba lagi sebentar.',
  );
  static String get fillGapsTitle =>
      _s('A few more things', 'Beberapa hal lagi');
  static String get parseFailed => _s(
    'Could not read that. Your text is safe — retry, or fill it in by hand.',
    'Tidak terbaca. Teks kamu aman — coba lagi, atau isi manual.',
  );
  static String get offline => _s(
    'No connection. Your text is safe — retry, or fill it in by hand.',
    'Tidak ada koneksi. Teks kamu aman — coba lagi, atau isi manual.',
  );
  static String get rateLimited => _s(
    'Daily limit reached. Your text is safe — fill it in by hand for now.',
    'Batas harian tercapai. Teks kamu aman — isi manual dulu.',
  );
  static String get retry => _s('Retry', 'Coba lagi');
  static String get byHand => _s('Fill in by hand', 'Isi manual');
  static String get pickMethod =>
      _s('What did you brew it with?', 'Pakai alat apa?');

  /// Deliberately a question about *enjoyment*, not quality. The number
  /// above it is the app's opinion; this is the only place the brewer's own
  /// taste gets recorded, and "What did you think?" was vague enough that it
  /// read as a second score.
  static String get rateThis =>
      _s('Did you enjoy this coffee?', 'Kamu suka nggak sama kopi ini?');
  static String get scoreThisBrew => _s('Score this brew', 'Nilai seduhan ini');

  /// Shown under a field the app filled in from an earlier brew.
  ///
  /// A remembered value is saved data that nobody has confirmed. With four
  /// fields that was survivable; with forty it is not, and it must not look
  /// identical to something you typed.
  static String get remembered => _s('remembered', 'diingat');
  static String get fromYourText => _s('from your text', 'dari teks kamu');
  static String get whatYouTyped => _s('What you typed', 'Yang kamu tulis');
  static String get deleteTitle =>
      _s('Delete this brew?', 'Hapus seduhan ini?');
  static String get deleteBody => _s(
    'It moves to Deleted entries in Settings, where you can bring it '
        'back or remove it for good.',
    'Pindah ke Catatan terhapus di Pengaturan, bisa dikembalikan atau '
        'dihapus permanen.',
  );
  static String get delete => _s('Delete', 'Hapus');
  static String get cancel => _s('Cancel', 'Batal');
  static String get yes => _s('Yes', 'Ya');
  static String get no => _s('No', 'Tidak');
  static String get fullLogTitle => _s('Full log', 'Catatan lengkap');
  static String get editTitle => _s('Edit', 'Ubah');
  static String get scoreLabel => _s('Score', 'Nilai');
  static String get settingsTitle => _s('Settings', 'Pengaturan');
  static String get reminderTitle => _s('Daily reminder', 'Pengingat harian');
  static String get reminderSubtitle => _s(
    'Only on days you have not logged a coffee.',
    'Hanya di hari kamu belum mencatat kopi.',
  );
  static String get reminderBlocked => _s(
    'Notifications are turned off for this app in Android settings.',
    'Notifikasi aplikasi ini dimatikan di pengaturan Android.',
  );
  static String get reminderTime => _s('Remind me at', 'Ingatkan pukul');
  static String get notificationBody =>
      _s('No coffee logged yet today.', 'Belum ada kopi dicatat hari ini.');
  static String get languageTitle => _s('Language', 'Bahasa');
  static String get deletedTitle => _s('Deleted entries', 'Catatan terhapus');
  static String get deletedSubtitle =>
      _s('Bring a brew back, or remove it', 'Kembalikan atau hapus permanen');
  static String get deletedOn => _s('Deleted', 'Dihapus');
  static String get emptyDeleted => _s('Nothing deleted.', 'Tidak ada.');
  static String get restore => _s('Restore', 'Kembalikan');
  static String get purge => _s('Delete for good', 'Hapus permanen');
  static String get purgeTitle => _s('Delete for good?', 'Hapus permanen?');
  static String get purgeBody =>
      _s('This cannot be undone.', 'Tidak bisa dibatalkan.');
  static String get rememberedTitle =>
      _s('Remembered for next time', 'Diingat untuk nanti');
  static String get rememberedSubtitle => _s(
    'Filled in automatically. Say something different and it updates.',
    'Terisi otomatis. Sebut yang lain dan ini berubah.',
  );
  static String get rememberedEmpty =>
      _s('Nothing yet — log a brew.', 'Belum ada — catat seduhan dulu.');

  static String get signInTitle => _s('Sign in', 'Masuk');
  static String get signInWhy => _s(
    'Your log lives on this phone. Sign in to back it up, so a lost or '
        'reset phone is not a lost logbook.',
    'Catatanmu ada di HP ini. Masuk untuk mencadangkan, supaya HP hilang '
        'atau direset tidak menghapus catatanmu.',
  );
  static String get signInGoogle =>
      _s('Continue with Google', 'Lanjut dengan Google');
  static String get signInEmail => _s('Use email', 'Pakai email');
  static String get signInPhone => _s('Use phone number', 'Pakai nomor HP');
  static String get emailLabel => _s('Email', 'Email');
  static String get passwordLabel => _s('Password', 'Kata sandi');
  static String get phoneLabel => _s('Phone number', 'Nomor HP');
  static String get codeLabel => _s('6-digit code', 'Kode 6 digit');
  static String get sendCode => _s('Send code', 'Kirim kode');
  static String get confirmCode => _s('Confirm', 'Konfirmasi');
  static String get createAccount => _s('Create account', 'Buat akun');
  static String get needAccount => _s('No account yet?', 'Belum punya akun?');
  static String get haveAccount => _s('Already have one?', 'Sudah punya akun?');
  static String get forgotPassword => _s('Forgot password', 'Lupa sandi');
  static String get resetSent =>
      _s('Reset email sent.', 'Email atur ulang terkirim.');
  static String get authWrongPassword =>
      _s('Wrong email or password.', 'Email atau sandi salah.');
  static String get authNeedsLinking => _s(
    'That email already has an account. Sign in the way you did before.',
    'Email itu sudah punya akun. Masuk dengan cara yang dulu kamu pakai.',
  );
  static String get authFailed => _s('Could not sign in.', 'Gagal masuk.');
  static String get backupTitle => _s('Backup', 'Cadangan');
  static String get backupSignedOut => _s(
    'Not signed in — this log is only on this phone.',
    'Belum masuk — catatan ini hanya ada di HP ini.',
  );
  static String get backupNever =>
      _s('Not backed up yet', 'Belum pernah dicadangkan');
  static String get backupNow => _s('Back up now', 'Cadangkan sekarang');
  static String get restoreNow =>
      _s('Restore from backup', 'Pulihkan cadangan');
  static String get signOut => _s('Sign out', 'Keluar');
  static String get backupWorking => _s('Backing up…', 'Mencadangkan…');
  static String get backupFailed =>
      _s("Couldn't back up — will retry", 'Gagal mencadangkan — akan diulang');

  static String backupDone(int n) =>
      _s('Backed up $n brews', '$n seduhan dicadangkan');
  static String restoreDone(int n) =>
      _s('Restored $n brews', '$n seduhan dipulihkan');
  static String codeSentTo(String phone) =>
      _s('Code sent to $phone', 'Kode dikirim ke $phone');

  /// The brew's own timestamp. Deliberately not "date added": the entry
  /// records when the coffee was made, and when it was written down is
  /// separate — and less interesting.
  /// Shown under the basket picker when a pressurised basket is chosen.
  ///
  /// The scorer already stops deducting for skipped WDT there, but a number
  /// that quietly declines to punish you teaches nothing. This says why.
  static String get pressurisedNote => _s(
    'On a pressurised basket the pressure comes from the hole in the second '
        'wall, not from the coffee. WDT and distribution have little to do '
        'here — levelling the bed is enough, by tamp or distributor. Not '
        'scored against you.',
    'Di basket pressurized, tekanan datang dari lubang di dinding kedua, '
        'bukan dari kopinya. WDT dan distribusi nggak banyak ngaruh di sini '
        '— yang penting bubuknya rata, mau pakai tamper atau distributor. '
        'Nggak dihitung mengurangi nilai.',
  );

  /// Shown after an edit re-scores a brew.
  ///
  /// The number used to change in silence, which reads as the app having
  /// second thoughts rather than as a consequence of the edit.
  static String get scoreChangedTitle => _s('Score changed', 'Nilai berubah');
  static String get scoreSameTitle =>
      _s('Score unchanged', 'Nilai tidak berubah');
  static String get scoreChangedWhy => _s(
    'You changed the brew, so it was scored again.',
    'Kamu mengubah seduhannya, jadi dinilai ulang.',
  );
  static String get scoreSameWhy => _s(
    'Scored again after your edit, and it landed on the same number.',
    'Dinilai ulang setelah kamu ubah, dan hasilnya sama.',
  );

  /// The honest caveat when the rubric moved underneath an old entry: the
  /// difference may be the scale, not the coffee.
  static String get scoreRubricMoved => _s(
    'The scoring rules also changed since this brew was last scored, so part '
        'of the difference is the rules rather than your edit.',
    'Aturan penilaiannya juga berubah sejak terakhir dinilai, jadi sebagian '
        'selisihnya karena aturan, bukan karena editanmu.',
  );
  static String get scoreRetryFailed => _s(
    'Could not score it again — the previous score is kept.',
    'Gagal menilai ulang — nilai sebelumnya dipertahankan.',
  );
  static String get ok => _s('OK', 'OK');

  static String get buildTitle => _s('Build', 'Versi terpasang');

  static String get creditsTitle => _s('Photo credits', 'Kredit foto');
  static String get creditsIntro => _s(
    'Every photograph here comes from Wikimedia Commons and is used under '
        'its own licence. Naming the author is a condition of that licence, '
        'not a courtesy.',
    'Semua foto di sini dari Wikimedia Commons dan dipakai sesuai lisensinya '
        'masing-masing. Mencantumkan fotografernya itu syarat lisensi, bukan '
        'sekadar basa-basi.',
  );

  static String get brewedAt => _s('Brewed at', 'Diseduh pada');
  static String get brewedAtFromText =>
      _s('from what you typed', 'dari yang kamu tulis');

  static String get searchHint => _s('Search your brews', 'Cari di catatanmu');
  static String get filterMethod => _s('Method', 'Metode');
  static String get filterRating => _s('Rating', 'Bintang');
  static String get filterAny => _s('Any', 'Semua');
  static String get filterClear => _s('Clear', 'Hapus filter');
  static String get noMatches =>
      _s('Nothing matches that.', 'Tidak ada yang cocok.');

  /// Shown whenever a filter is on, so a short list never reads as data loss.
  static String matchCount(int shown, int total) =>
      _s('$shown of $total', '$shown dari $total');
  static String atLeastStars(int n) =>
      _s('${'★' * n} and up', '${'★' * n} ke atas');

  static String get guidesTitle => _s('How to brew', 'Cara menyeduh');
  static String get guidesIntro => _s(
    'Targets here are the same ones the app scores against, so following a '
        'guide cannot cost you points.',
    'Target di sini sama dengan yang dipakai untuk menilai, jadi mengikuti '
        'panduan tidak akan mengurangi nilaimu.',
  );
  static String get guideTargets => _s('Aim for', 'Targetkan');
  static String get guideRatio => _s('Ratio', 'Rasio');
  static String get guideTime => _s('Time', 'Waktu');
  static String get guideTemp => _s('Water', 'Air');
  static String get guideGrind => _s('Grind', 'Gilingan');
  static String get guideHow => _s('How to brew it', 'Cara menyeduhnya');
  static String get guideFaults =>
      _s('When it goes wrong', 'Kalau hasilnya meleset');
  static String get guideGear => _s('Gear', 'Peralatan');
  static String get guideNotes => _s('Worth knowing', 'Perlu diketahui');
  static String get guideMissing => _s('No guide yet.', 'Belum ada panduan.');

  static String groupLabel(FieldGroup g) => switch (g) {
    FieldGroup.coffee => _s('Coffee', 'Kopi'),
    FieldGroup.grind => _s('Grind', 'Gilingan'),
    FieldGroup.brew => _s('Brew', 'Seduhan'),
    FieldGroup.water => _s('Water', 'Air'),
  };

  /// Only for `test/language_test.dart`, which checks that nothing was copied
  /// across untranslated.
  static Map<String, String> get all => {
    'appName': appName,
    'newEntryTitle': newEntryTitle,
    'describeHint': describeHint,
    'parseButton': parseButton,
    'parsing': parsing,
    'scoring': scoring,
    'saveButton': saveButton,
    'doneButton': doneButton,
    'emptyLog': emptyLog,
    'notScored': notScored,
    'scoreFailed': scoreFailed,
    'scoreUnavailable': scoreUnavailable,
    'fillGapsTitle': fillGapsTitle,
    'parseFailed': parseFailed,
    'offline': offline,
    'rateLimited': rateLimited,
    'retry': retry,
    'byHand': byHand,
    'pickMethod': pickMethod,
    'rateThis': rateThis,
    'scoreThisBrew': scoreThisBrew,
    'remembered': remembered,
    'fromYourText': fromYourText,
    'whatYouTyped': whatYouTyped,
    'deleteTitle': deleteTitle,
    'deleteBody': deleteBody,
    'delete': delete,
    'cancel': cancel,
    'yes': yes,
    'no': no,
    'fullLogTitle': fullLogTitle,
    'editTitle': editTitle,
    'scoreLabel': scoreLabel,
    'settingsTitle': settingsTitle,
    'reminderTitle': reminderTitle,
    'reminderSubtitle': reminderSubtitle,
    'reminderBlocked': reminderBlocked,
    'reminderTime': reminderTime,
    'notificationBody': notificationBody,
    'languageTitle': languageTitle,
    'deletedTitle': deletedTitle,
    'deletedSubtitle': deletedSubtitle,
    'deletedOn': deletedOn,
    'emptyDeleted': emptyDeleted,
    'restore': restore,
    'purge': purge,
    'purgeTitle': purgeTitle,
    'purgeBody': purgeBody,
    'rememberedTitle': rememberedTitle,
    'rememberedSubtitle': rememberedSubtitle,
    'rememberedEmpty': rememberedEmpty,
    'noChanges': noChanges,
    'pressurisedNote': pressurisedNote,
    'scoreChangedTitle': scoreChangedTitle,
    'scoreSameTitle': scoreSameTitle,
    'scoreChangedWhy': scoreChangedWhy,
    'scoreSameWhy': scoreSameWhy,
    'scoreRubricMoved': scoreRubricMoved,
    'scoreRetryFailed': scoreRetryFailed,
    'buildTitle': buildTitle,
    'creditsTitle': creditsTitle,
    'creditsIntro': creditsIntro,
    'brewedAt': brewedAt,
    'brewedAtFromText': brewedAtFromText,
    'searchHint': searchHint,
    'filterMethod': filterMethod,
    'filterRating': filterRating,
    'filterAny': filterAny,
    'filterClear': filterClear,
    'noMatches': noMatches,
    'guidesTitle': guidesTitle,
    'guidesIntro': guidesIntro,
    'guideTargets': guideTargets,
    'guideRatio': guideRatio,
    'guideTime': guideTime,
    'guideTemp': guideTemp,
    'guideGrind': guideGrind,
    'guideHow': guideHow,
    'guideFaults': guideFaults,
    'guideGear': guideGear,
    'guideNotes': guideNotes,
    'guideMissing': guideMissing,
    'signInTitle': signInTitle,
    'signInWhy': signInWhy,
    'signInGoogle': signInGoogle,
    'signInEmail': signInEmail,
    'signInPhone': signInPhone,
    'emailLabel': emailLabel,
    'passwordLabel': passwordLabel,
    'phoneLabel': phoneLabel,
    'codeLabel': codeLabel,
    'sendCode': sendCode,
    'confirmCode': confirmCode,
    'createAccount': createAccount,
    'needAccount': needAccount,
    'haveAccount': haveAccount,
    'forgotPassword': forgotPassword,
    'resetSent': resetSent,
    'authWrongPassword': authWrongPassword,
    'authNeedsLinking': authNeedsLinking,
    'authFailed': authFailed,
    'backupTitle': backupTitle,
    'backupSignedOut': backupSignedOut,
    'backupNever': backupNever,
    'backupNow': backupNow,
    'restoreNow': restoreNow,
    'signOut': signOut,
    'backupWorking': backupWorking,
    'backupFailed': backupFailed,
  };
}
