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
  static String get doneButton => _s('Done', 'Selesai');
  static String get emptyLog =>
      _s('No brews yet. Tap + to log one.', 'Belum ada. Ketuk + untuk mulai.');
  static String get notScored => _s('Not scored', 'Tidak dinilai');
  static String get scoreFailed =>
      _s('Not scored yet — tap to retry', 'Belum dinilai — ketuk untuk ulang');
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
  static String get rateThis => _s('What did you think?', 'Menurutmu gimana?');
  static String get scoreThisBrew => _s('Score this brew', 'Nilai seduhan ini');
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

  static String stickyLabel(String name) => switch (name) {
    'grinder' => _s('Grinder', 'Penggiling'),
    'grindSetting' => _s('Grind setting', 'Setelan giling'),
    'waterType' => _s('Water', 'Air'),
    'machine' => _s('Machine', 'Mesin'),
    _ => name,
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
    'fillGapsTitle': fillGapsTitle,
    'parseFailed': parseFailed,
    'offline': offline,
    'rateLimited': rateLimited,
    'retry': retry,
    'byHand': byHand,
    'pickMethod': pickMethod,
    'rateThis': rateThis,
    'scoreThisBrew': scoreThisBrew,
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
