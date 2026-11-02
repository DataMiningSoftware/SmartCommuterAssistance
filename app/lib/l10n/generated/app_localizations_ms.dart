// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Malay (`ms`).
class AppLocalizationsMs extends AppLocalizations {
  AppLocalizationsMs([String locale = 'ms']) : super(locale);

  @override
  String get appTitle => 'Smart Commuter Assistant+';

  @override
  String get navHome => 'Utama';

  @override
  String get navMap => 'Peta';

  @override
  String get navTrack => 'Jejak';

  @override
  String get navRace => 'Lumba';

  @override
  String get navProfile => 'Profil';

  @override
  String closingIn(String time) {
    return 'Tren akan berhenti dalam $time';
  }

  @override
  String get dataLive => 'LANGSUNG';

  @override
  String get dataOffline => 'LUAR TALIAN';

  @override
  String get crowdLevelEmpty => 'Kosong';

  @override
  String get crowdLevelLight => 'Ringan';

  @override
  String get crowdLevelModerate => 'Sederhana';

  @override
  String get crowdLevelHeavy => 'Padat';

  @override
  String get crowdLevelCrowded => 'Sesak';

  @override
  String get crowdLevelUnknown => 'Tidak diketahui';

  @override
  String get mapSubtitle => 'Paparan geografi dan skematik';

  @override
  String get mapGeographic => 'Geografi';

  @override
  String get mapTransitMap => 'Peta transit';

  @override
  String get mapStationHint => 'Stesen';

  @override
  String mapLoadFailed(String error) {
    return 'Gagal memuatkan data peta: $error';
  }

  @override
  String get mapTapAnotherStation =>
      'Ketik stesen lain untuk merancang laluan dari sini.';

  @override
  String get mapFindingRoute => 'Mencari laluan terbaik...';

  @override
  String mapRouteSummary(String duration, String transfers, String crowd) {
    return '$duration · $transfers · kesesakan $crowd';
  }

  @override
  String get mapChooseDifferent => 'Pilih yang lain';

  @override
  String get mapStartJourney => 'Mula perjalanan';

  @override
  String get mapJourneyStarted =>
      'Perjalanan bermula — penjejakan di tab Jejak.';

  @override
  String get mapSchematicA11yLabel =>
      'Peta transit. Ketik stesen untuk memilihnya.';

  @override
  String get mapZoomIn => 'Zum masuk';

  @override
  String get mapZoomOut => 'Zum keluar';

  @override
  String get dataSourceScheduled => 'Dijadualkan';

  @override
  String get dataSourceRiderReport => 'Laporan penumpang';

  @override
  String get dataSourceBlended => 'Gabungan';

  @override
  String get dataSourceEstimated => 'Anggaran';

  @override
  String get dataSourceClosed => 'Tutup';

  @override
  String get dataSourceFallback => 'Sandaran';

  @override
  String get dataSourceUnknown => 'Tidak diketahui';

  @override
  String get connectivityConnected => 'Anda telah bersambung';

  @override
  String get connectivityDisconnected => 'Sambungan terputus';

  @override
  String get offlineTitle => 'Anda di luar talian';

  @override
  String get offlineBody =>
      'Sesetengah ciri memerlukan sambungan internet. Stesen yang disimpan, laluan tersimpan dan anggaran kesesakan tempatan masih berfungsi.';

  @override
  String get tryAgain => 'Cuba lagi';

  @override
  String get continueOffline => 'Teruskan luar talian';

  @override
  String get configurationRequired => 'Konfigurasi Diperlukan';

  @override
  String get retry => 'Cuba lagi';

  @override
  String get preparingData => 'Menyediakan data perjalanan anda...';

  @override
  String startupFailed(String error) {
    return 'Gagal memulakan aplikasi.\n\n$error';
  }

  @override
  String get languageTitle => 'Bahasa';

  @override
  String get languageSystemOption => 'Ikut sistem';

  @override
  String get languageEnglishOption => 'English';

  @override
  String get languageMalayOption => 'Bahasa Melayu';

  @override
  String get profileCommuter => 'Komuter';

  @override
  String get profileUserFallback => 'Pengguna';

  @override
  String get profileNoAccount => 'Tiada akaun diperlukan — laporan tanpa nama';

  @override
  String get profileEditTooltip => 'Sunting profil';

  @override
  String get preferencesTitle => 'Keutamaan';

  @override
  String get pushNotificationsTitle => 'Pemberitahuan Push';

  @override
  String get pushNotificationsSubtitle => 'Makluman kelewatan dan laluan';

  @override
  String get offlineModeTitle => 'Mod Luar Talian';

  @override
  String get offlineModeSubtitle => 'Simpan jadual untuk liputan lemah';

  @override
  String get locationSharingTitle => 'Perkongsian Lokasi';

  @override
  String get locationSharingSubtitle =>
      'Digunakan untuk stesen berdekatan; dihantar dibundarkan ~1 km';

  @override
  String get mlConsentTitle => 'Tingkatkan ramalan dengan data perjalanan saya';

  @override
  String get mlConsentSubtitle =>
      'Pilihan. Menggunakan laporan dan masa perjalanan anda untuk latihan model';

  @override
  String get accessibilityTitle => 'Kebolehaksesan';

  @override
  String get accessibilitySubtitle =>
      'Label lebih besar dan kontras lebih tinggi';

  @override
  String get darkModeTitle => 'Mod Gelap';

  @override
  String get darkModeSubtitle => 'Aktifkan tema gelap untuk aplikasi';

  @override
  String get dataAttributionsTitle => 'Atribusi Data';

  @override
  String get mapTilesTitle => 'Jubin peta';

  @override
  String get mapTilesSource => '© CartoDB';

  @override
  String get weatherTitle => 'Cuaca';

  @override
  String get weatherSource => 'Data cuaca oleh Open-Meteo.com';

  @override
  String get transitScheduleTitle => 'Jadual transit';

  @override
  String get transitScheduleSource =>
      '© Prasarana Malaysia melalui data.gov.my';

  @override
  String get quickActionsTitle => 'Tindakan Pantas';

  @override
  String get routeBuilderTitle => 'Pembina Laluan';

  @override
  String get friendsTitle => 'Rakan';

  @override
  String get learnTheRailsTitle => 'Kenali Rel';

  @override
  String get favoriteRoutesTitle => 'Laluan Kegemaran';

  @override
  String get travelHistoryTitle => 'Sejarah Perjalanan';

  @override
  String get testNotificationTitle => 'Uji pemberitahuan';

  @override
  String get testNotificationBody => 'Ini pemberitahuan ujian. 🚆';

  @override
  String get helpSupportTitle => 'Bantuan & Sokongan';

  @override
  String get aboutTitle => 'Perihal';

  @override
  String get privacyPolicyTitle => 'Dasar Privasi';

  @override
  String get logoutButton => 'Log Keluar';

  @override
  String get deleteMyDataButton => 'Padam data saya';

  @override
  String get deleteAccountButton => 'Padam Akaun';

  @override
  String get profileDeleteDataDialogTitle => 'Padam data saya?';

  @override
  String get profileDeleteAccountDialogTitle => 'Padam akaun?';

  @override
  String get profileDeleteDataDialogBody =>
      'Ini akan memadamkan profil peranti tanpa nama, akaun dan maklum balas perjalanan anda secara kekal. Laporan sumbangan anda akan dinyahpaut dan dianonimkan. Tindakan ini tidak boleh dibatalkan.';

  @override
  String get profileDeleteAccountDialogBody =>
      'Ini akan memadamkan akaun, profil dan sejarah perjalanan anda secara kekal. Laporan sumbangan anda akan dinyahpaut dan dianonimkan. Tindakan ini tidak boleh dibatalkan.';

  @override
  String get cancelButton => 'Batal';

  @override
  String get deleteButton => 'Padam';

  @override
  String get accountDeleted => 'Akaun dipadam.';

  @override
  String get deleteAccountFailed =>
      'Akaun tidak dapat dipadam secara automatik. Sila gunakan pautan pemadaman akaun dalam dasar privasi.';

  @override
  String get editProfileTitle => 'Sunting Profil';

  @override
  String get handleLabel => 'Nama panggilan';

  @override
  String get displayNameLabel => 'Nama paparan';

  @override
  String get bioLabel => 'Bio';

  @override
  String get avatarColorLabel => 'Warna avatar (hex, pilihan)';

  @override
  String get homeStationLabel => 'ID stesen rumah (pilihan)';

  @override
  String get favoriteLineLabel => 'Laluan kegemaran (pilihan)';

  @override
  String get allowFindByHandle =>
      'Benarkan orang lain mencari saya melalui nama panggilan';

  @override
  String get saveButton => 'Simpan';

  @override
  String get aboutDialogTitle => 'Perihal Smart Commuter Assistant+';

  @override
  String aboutDialogBody(String version) {
    return 'Smart Commuter Assistant+ v$version\n\nNavigasi Dinamik & Pengiraan Kesesakan.\n\nRakan pintar untuk pengangkutan awam Malaysia.\n\nAplikasi bebas dan tidak rasmi — tidak berkaitan dengan Rapid KL, Prasarana Malaysia atau KTMB.';
  }

  @override
  String get okButton => 'OK';

  @override
  String get railIndependenceTitle => 'Kebebasan Rel Anda';

  @override
  String railIndependenceBody(int stations, int accuracy) {
    String _temp0 = intl.Intl.pluralLogic(
      stations,
      locale: localeName,
      other: 'stesen',
      one: 'stesen',
    );
    return 'Anda mengenali $stations $_temp0 dan menjawab $accuracy% soalan kuiz dengan betul. Teruskan — matlamatnya ialah tidak memerlukan kami.';
  }

  @override
  String get locationServicesOff =>
      'Hidupkan Perkhidmatan Lokasi untuk menggunakan stesen berdekatan.';

  @override
  String get locationPermissionDenied =>
      'Kebenaran lokasi ditolak dalam tetapan sistem.';

  @override
  String get loginWelcome => 'Selamat kembali';

  @override
  String get loginSubtitle =>
      'Log masuk untuk melihat ramalan, laluan dan sejarah perjalanan anda.';

  @override
  String get emailLabel => 'E-mel';

  @override
  String get passwordLabel => 'Kata laluan';

  @override
  String get confirmPasswordLabel => 'Sahkan kata laluan';

  @override
  String get emailRequired => 'E-mel diperlukan';

  @override
  String get emailInvalid => 'Masukkan e-mel yang sah';

  @override
  String get passwordRequired => 'Kata laluan diperlukan';

  @override
  String get passwordMinLength => 'Gunakan sekurang-kurangnya 6 aksara';

  @override
  String get passwordsDoNotMatch => 'Kata laluan tidak sepadan';

  @override
  String get nameRequired => 'Nama diperlukan';

  @override
  String get fullNameLabel => 'Nama penuh';

  @override
  String get signingIn => 'Sedang log masuk…';

  @override
  String get loginButton => 'Log Masuk';

  @override
  String get signInWithGoogleButton => 'Log masuk dengan Google';

  @override
  String get guestModeEnabled =>
      'Mod tetamu diaktifkan. Anda boleh teruskan tanpa akaun.';

  @override
  String get guestModeFailed =>
      'Tidak dapat memasuki mod tetamu sekarang. Sila cuba lagi.';

  @override
  String get continueAsGuestButton => 'Teruskan sebagai tetamu';

  @override
  String get createAccountButton => 'Cipta akaun';

  @override
  String get signInWithPhoneButton => 'Log masuk dengan telefon';

  @override
  String get signUpTitle => 'Cipta Pas Anda';

  @override
  String get creatingAccount => 'Sedang mencipta…';

  @override
  String get accountCreatedVerify =>
      'Akaun dicipta! Semak e-mel anda untuk mengesahkannya, kemudian log masuk.';

  @override
  String get phoneNumberLabel => 'Nombor telefon';

  @override
  String get phoneNumberHint => '+60 12-345 6789';

  @override
  String get verificationCodeLabel => 'Kod pengesahan';

  @override
  String get pleaseWait => 'Sila tunggu…';

  @override
  String get verifyCodeButton => 'Sahkan kod';

  @override
  String get sendCodeButton => 'Hantar kod';

  @override
  String get otpInfo =>
      'Kod sekali guna akan dihantar melalui SMS. Memerlukan penyedia Phone diaktifkan dalam Supabase.';

  @override
  String get supportContactTitle => 'E-mel pembangun';

  @override
  String get supportContactBody =>
      'Soalan, laporan pepijat atau idea ciri? Kami biasanya membalas dalam beberapa hari.';

  @override
  String get supportSendEmailButton => 'Hantar e-mel';

  @override
  String get supportCopyEmailButton => 'Salin alamat e-mel';

  @override
  String get supportEmailCopied => 'Alamat e-mel disalin';

  @override
  String get supportNoMailApp =>
      'Tiada aplikasi e-mel ditemui — alamat telah disalin';

  @override
  String get supportFaqTitle => 'Soalan lazim';

  @override
  String get supportFaqOfflineQuestion =>
      'Mengapa sesetengah ciri tidak berfungsi di luar talian?';

  @override
  String get supportFaqOfflineAnswer =>
      'Ketibaan langsung, ramalan kesesakan dan perancangan laluan memerlukan sambungan. Stesen, laluan tersimpan dan ramalan terakhir yang disimpan masih berfungsi dalam mod luar talian.';

  @override
  String get supportFaqCrowdQuestion =>
      'Dari mana ramalan kesesakan diperoleh?';

  @override
  String get supportFaqCrowdAnswer =>
      'Ramalan setiap jam dilatih menggunakan laporan penumpang dan digabungkan dengan laporan komuniti terkini. Laporan yang disahkan daripada penumpang berbeza diberi keutamaan.';

  @override
  String get supportFaqDelayQuestion =>
      'Bagaimana laporan kelewatan berfungsi?';

  @override
  String get supportFaqDelayAnswer =>
      'Apabila sekurang-kurangnya 3 penumpang melaporkan kelewatan pada laluan dan arah yang sama dalam masa 20 minit, penumpang lain akan melihat isyarat kelewatan dan ETA mereka dilaraskan secara automatik.';

  @override
  String get supportFaqPrivacyQuestion => 'Apa yang berlaku kepada data saya?';

  @override
  String get supportFaqPrivacyAnswer =>
      'Aplikasi ini berfungsi tanpa nama tanpa akaun. Lokasi kekal pada peranti anda kecuali laporan kesesakan yang dibundarkan (~1 km) yang anda pilih untuk hantar. Anda boleh memadam semuanya dari Profil.';

  @override
  String get supportFaqEtaQuestion => 'Sejauh mana ketepatan ETA?';

  @override
  String get supportFaqEtaAnswer =>
      'ETA ditetapkan apabila anda tiba di stesen asal dan dikira turun dengan stabil. Ia dilaraskan berdasarkan laporan kelewatan dan kesesakan, dan bertambah baik dari semasa ke semasa.';

  @override
  String get supportLinksTitle => 'Lain-lain';

  @override
  String get supportDeleteDataLink => 'Padam data anda (web)';

  @override
  String get supportIssuesLink => 'Laporkan isu di GitHub';

  @override
  String supportEmailSubject(String version) {
    return '[Smart Commuter Assistant+] Sokongan — v$version';
  }

  @override
  String supportEmailBody(String version, String build, String platform,
      String locale, String connection) {
    return 'Terangkan isu anda di sini.\n\n---\nAplikasi: Smart Commuter Assistant+ $version ($build)\nPlatform: $platform\nBahasa: $locale\nSambungan: $connection\n---';
  }

  @override
  String homeStationUnavailableClosingHours(String station) {
    return '$station tidak tersedia semasa waktu tutup untuk masa berlepas yang dipilih.';
  }

  @override
  String get homeLocationRequired =>
      'Lokasi diperlukan sebelum memulakan perjalanan.';

  @override
  String get homeNearestStationUnavailable =>
      'Belum dapat menentukan stesen terdekat anda.';

  @override
  String homeNoRouteFound(String station) {
    return 'Tiada laluan ditemui untuk $station.';
  }

  @override
  String homePrepareTripFailed(String error) {
    return 'Tidak dapat menyediakan perjalanan: $error';
  }

  @override
  String get homeRouteCrowdedTitle => 'Nampaknya laluan anda sesak.';

  @override
  String homeCalmerTripAvailable(String destination) {
    return 'Perjalanan yang lebih tenang ke $destination tersedia, tetapi mungkin mengambil masa lebih lama.';
  }

  @override
  String get homeEfficientRoute => 'Laluan cekap';

  @override
  String get homeFastestOptionNow => 'Pilihan terpantas sekarang';

  @override
  String get homeKeepThisRoute => 'Kekalkan laluan ini';

  @override
  String get homeRelaxedRoute => 'Laluan santai';

  @override
  String get homeCalmerRideDetour =>
      'Perjalanan lebih tenang dengan lencongan kecil';

  @override
  String get homeTakeRelaxedRoute => 'Ambil laluan yang lebih santai';

  @override
  String get homeLocationPrivacyTitle => 'Privasi Lokasi';

  @override
  String get homeLocationPrivacyBody =>
      'Lokasi anda digunakan untuk mencari stesen berdekatan dan memberikan anggaran ketibaan. Koordinat dibundarkan kepada ketepatan ~1 km sebelum dihantar ke pelayan kami. Lokasi tepat anda tidak pernah disimpan atau dikongsi.\n\nAnda boleh mengubahnya kemudian dalam tetapan Profil.';

  @override
  String get homeSkip => 'Langkau';

  @override
  String get homeAllow => 'Benarkan';

  @override
  String homeCrowdLevelsLower(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tahap kesesakan lebih rendah',
      one: '1 tahap kesesakan lebih rendah',
    );
    return '$_temp0';
  }

  @override
  String homeCrowdLevelsHigher(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tahap kesesakan lebih tinggi',
      one: '1 tahap kesesakan lebih tinggi',
    );
    return '$_temp0';
  }

  @override
  String get homeFastest => 'Terpantas';

  @override
  String get homeNoTimePenalty => 'Tiada penalti masa';

  @override
  String homePlusMinutes(int minutes) {
    return '+$minutes minit';
  }

  @override
  String get homeDirectRide => 'Perjalanan terus';

  @override
  String homeTransferCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pertukaran',
      one: '1 pertukaran',
    );
    return '$_temp0';
  }

  @override
  String get homeSubtitle => 'Hab utama';

  @override
  String get homeHeroTitle => 'Naik dengan bijak, elak kesesakan.';

  @override
  String get homeHeroSubtitle =>
      'Laluan peka kesesakan langsung, penjejakan perjalanan dan sorotan laluan di satu tempat.';

  @override
  String get homeAllStations => 'Semua Stesen';

  @override
  String get homeAllStationsSubtitle => 'Layari laluan dan pertukaran';

  @override
  String get homeTrackRoute => 'Jejak Laluan';

  @override
  String get homeResumeTrip => 'Sambung Perjalanan';

  @override
  String get homeStartTripHint => 'Mulakan perjalanan untuk membuka penjejakan';

  @override
  String homeTripDirection(String origin, String destination) {
    return '$origin ke $destination';
  }

  @override
  String get homeRouteModeAuto => 'Auto';

  @override
  String get homeRouteModeEfficient => 'Cekap';

  @override
  String get homeRouteModeRelaxed => 'Santai';

  @override
  String get homeRouteModeAutoHelper =>
      'Bandingkan laluan cekap dan santai, kemudian tanya hanya apabila laluan lebih tenang berbaloi.';

  @override
  String get homeRouteModeEfficientHelper =>
      'Sentiasa kekalkan laluan terpantas.';

  @override
  String get homeRouteModeComfortHelper =>
      'Utamakan kesesakan lebih rendah walaupun perjalanan mengambil masa sedikit lebih lama.';

  @override
  String get homePickNextStop => 'Pilih Hentian Seterusnya';

  @override
  String get homeSearchDestinationHint =>
      'Cari destinasi, tetapkan gaya laluan dan pratonton kesesakan sebelum anda bertolak.';

  @override
  String get homeRouteStyle => 'Gaya laluan';

  @override
  String get homeLoadingStations => 'Memuatkan stesen…';

  @override
  String homeLoadStationsFailed(String error) {
    return 'Gagal memuatkan stesen: $error';
  }

  @override
  String get homeNoStationNames =>
      'Belum ada nama stesen. Menunjukkan senarai contoh tempatan sebagai ganti.';

  @override
  String get homeSearchTrainStation => 'Cari stesen tren';

  @override
  String get homeClosingHours => 'Waktu tutup';

  @override
  String get homePlanAhead => 'Rancang Awal';

  @override
  String get homeLiveMapUnavailable => 'Peta langsung tidak tersedia';

  @override
  String get homeEtaSyncing => 'ETA sedang disegerakkan';

  @override
  String get homeArrivingNow => 'Tiba sekarang';

  @override
  String homeArriveBy(String time) {
    return 'Tiba pada $time';
  }

  @override
  String get homeLiveTrip => 'Perjalanan Langsung';

  @override
  String get homeViewMap => 'Lihat peta';

  @override
  String get homeRelaxedRoutingActive => 'Laluan santai sedang aktif.';

  @override
  String get homeLiveTrackingReady => 'Penjejakan langsung sedia.';

  @override
  String get homeYouAreHere => 'Anda di sini';

  @override
  String get homeMinutesShort => 'minit';

  @override
  String get homeGreeting => 'Ke mana hari ini?';

  @override
  String get homeFastRouteTitle => '⚡ Laluan pantas';

  @override
  String get homeLessCrowdedTitle => '🌿 Kurang sesak';

  @override
  String get homeKeepFastRoute => 'Kekal dengan laluan pantas';

  @override
  String get homeTakeLessCrowdedRoute => 'Ambil laluan kurang sesak';

  @override
  String get languageChineseOption => '中文';

  @override
  String get languageTamilOption => 'தமிழ்';

  @override
  String homeTripEtaTo(int minutes, String destination) {
    return '$minutes min ke $destination';
  }

  @override
  String get homeCrowdLevelPrefix => 'Tahap kesesakan: ';

  @override
  String get homeOpenTracking => 'Buka penjejakan';

  @override
  String get homeStationCrowdBoard => 'Papan Kesesakan Stesen';

  @override
  String get homeNearestStationSubtitle =>
      'Menunjukkan stesen terdekat dengan lokasi anda sekarang.';

  @override
  String get homeViewAll => 'Lihat semua';

  @override
  String get homeRefreshNearbyStations => 'Muat semula stesen berdekatan';

  @override
  String homeLoadCrowdBoardFailed(String error) {
    return 'Gagal memuatkan papan kesesakan: $error';
  }

  @override
  String get homeLocationSyncing =>
      'Lokasi masih disegerakkan. Tarik untuk muat semula atau cuba lagi sebentar lagi.';

  @override
  String homeMetersAway(String distance) {
    return '$distance m dari anda';
  }

  @override
  String get homeReportCrowded => 'Laporkan sesak';

  @override
  String homeEtaLabel(String duration) {
    return 'ETA $duration';
  }

  @override
  String homeDurationMinutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String homeDurationHoursShort(int hours) {
    return '$hours j';
  }

  @override
  String homeDurationHoursMinutesShort(int hours, int minutes) {
    return '${hours}j ${minutes}m';
  }

  @override
  String get homeRoutePending => 'Laluan belum sedia';

  @override
  String get trackKeepCrowdedRoute => 'Kekalkan laluan sesak';

  @override
  String get trackPlanYourTrip => 'Rancang Perjalanan Anda';

  @override
  String get trackSelectOriginDestination => 'Pilih stesen asal dan destinasi.';

  @override
  String get trackFromLabel => 'Dari';

  @override
  String get trackToLabel => 'Ke';

  @override
  String get trackSetArrivalTime => 'Tetapkan masa ketibaan';

  @override
  String get trackWhenArrive => 'Bila anda ingin tiba?';

  @override
  String get trackTargetArrivalHint =>
      'Tetapkan masa ketibaan sasaran anda dan kami akan mengira bila perlu bertolak.';

  @override
  String get trackCalculate => 'Kira';

  @override
  String get trackCalculatingSchedule => 'Mengira jadual...';

  @override
  String trackNoRouteFoundTo(String station) {
    return 'Tiada laluan ditemui ke $station.';
  }

  @override
  String trackPlanAheadFailed(String error) {
    return 'Tidak dapat merancang lebih awal: $error';
  }

  @override
  String get trackTripPlan => 'Rancangan Perjalanan';

  @override
  String get trackLeaveBy => 'Bertolak sebelum';

  @override
  String trackWalkTo(String station) {
    return 'Berjalan ke $station';
  }

  @override
  String trackDurationMinutes(int minutes) {
    return '$minutes minit';
  }

  @override
  String trackVia(String routes) {
    return 'Melalui $routes';
  }

  @override
  String trackArriveAt(String station) {
    return 'Tiba di $station';
  }

  @override
  String trackEstimatedTotal(int minutes) {
    return 'Jumlah anggaran: $minutes minit';
  }

  @override
  String get trackStartThisTripNow => 'Mulakan perjalanan ini sekarang';

  @override
  String trackStationUnavailableClosingHours(String station) {
    return '$station tidak tersedia semasa waktu tutup.';
  }

  @override
  String get trackEnableLocationServices =>
      'Hidupkan perkhidmatan lokasi sebelum memulakan perjalanan.';

  @override
  String get trackLocationPermissionRequired =>
      'Kebenaran lokasi diperlukan untuk memulakan perjalanan.';

  @override
  String trackChooseDestinationBeyond(String station) {
    return 'Pilih destinasi melebihi $station.';
  }

  @override
  String trackStartTripFailed(String error) {
    return 'Tidak dapat memulakan perjalanan: $error';
  }

  @override
  String trackSwitchDestinationFrom(String station) {
    return 'Tukar destinasi dari $station';
  }

  @override
  String get trackSwitchDestinationHint =>
      'Pilih stesen sasaran baharu dan laluan akan bermula semula dari lokasi anda sekarang.';

  @override
  String get trackSearchStationOrCode => 'Cari stesen atau kod';

  @override
  String get trackAreYouOkay => 'Adakah anda okay?';

  @override
  String get trackInactivityBody =>
      'Anda tidak bergerak sejak sekian lama. Adakah semuanya baik?';

  @override
  String get trackImFine => 'Saya okay';

  @override
  String get trackCallEmergencyContact => 'Hubungi kontak kecemasan';

  @override
  String get trackCancelTrip => 'Batal perjalanan';

  @override
  String get trackEmergencyDialer =>
      'Dailer kontak kecemasan akan dibuka di sini.';

  @override
  String get trackRouteRecalculated => 'Laluan dikira semula';

  @override
  String get trackDeviatedFromRoute =>
      'Anda telah tersasar dari laluan beberapa kali.';

  @override
  String get trackPickNewDestination =>
      'Adakah anda ingin memilih destinasi baharu?';

  @override
  String get trackContinueToDestination => 'Teruskan ke destinasi semasa';

  @override
  String get trackChooseNewDestination => 'Pilih destinasi baharu';

  @override
  String get trackLocatingTrain => 'Menjejak tren';

  @override
  String trackChangeLineAt(String station) {
    return 'Tukar laluan di $station';
  }

  @override
  String trackSwitchToLine(String routeId) {
    return 'Tukar ke laluan $routeId selepas stesen ini.';
  }

  @override
  String trackReachedDestination(String destination) {
    return 'Anda telah tiba di $destination';
  }

  @override
  String get trackTripEnded => 'Perjalanan anda telah tamat.';

  @override
  String trackRidersReportDelays(int count, String route, int minutes) {
    return '$count penumpang melaporkan kelewatan pada $route · +$minutes minit';
  }

  @override
  String get trackDelayReportFailed =>
      'Tidak dapat menghantar laporan kelewatan. Sila cuba lagi.';

  @override
  String trackCrowdedReported(String stopId) {
    return 'Tren sesak dilaporkan untuk $stopId.';
  }

  @override
  String trackDelayReported(String stopId) {
    return 'Kelewatan dilaporkan untuk $stopId.';
  }

  @override
  String trackReportSubmitFailed(String error) {
    return 'Tidak dapat menghantar laporan: $error';
  }

  @override
  String get trackCancelActiveTripTitle => 'Batal perjalanan aktif?';

  @override
  String get trackCancelActiveTripBody =>
      'Ini akan menghentikan penjejakan langsung dan memadamkan laluan yang disimpan.';

  @override
  String get trackKeepTrip => 'Kekalkan Perjalanan';

  @override
  String get trackTitleLeading => 'Perjalanan';

  @override
  String get trackTitleAccent => 'Gerak';

  @override
  String get trackTitleSubtitle => 'Penjejakan';

  @override
  String get trackPickStationFromResults =>
      'Pilih stesen daripada hasil carian.';

  @override
  String get trackPreparingTimeline => 'Menyediakan garis masa laluan...';

  @override
  String get trackSending => 'Menghantar...';

  @override
  String get trackReport => 'Lapor';

  @override
  String get trackSyncing => 'menyegerak';

  @override
  String get trackArrived => 'Tiba';

  @override
  String trackStopsRemaining(int count) {
    return '$count hentian';
  }

  @override
  String get trackTimeLeft => 'Masa berbaki';

  @override
  String get trackArriveBy => 'Tiba pada';

  @override
  String trackPercent(int percent) {
    return '$percent%';
  }

  @override
  String trackPercentCompleted(int percent) {
    return '$percent% selesai';
  }

  @override
  String get trackChangeDestination => 'Tukar destinasi';

  @override
  String trackChangeTo(String routeId) {
    return 'Tukar ke $routeId';
  }

  @override
  String get trackStartStation => 'Stesen permulaan';

  @override
  String get trackEndStation => 'Stesen akhir';

  @override
  String trackForecast(String label) {
    return 'Ramalan: $label';
  }

  @override
  String get trackCrowdedTrain => 'Tren sesak';

  @override
  String get trackDelay => 'Kelewatan';

  @override
  String get trackNoActiveTrip => 'Belum ada perjalanan aktif.';

  @override
  String get trackNoActiveTripBody =>
      'Cari destinasi di sini dan mula menjejak terus dari halaman jejak.';

  @override
  String get trackStartingTrip => 'Memulakan perjalanan...';

  @override
  String get trackSearch => 'Cari';

  @override
  String get trackPlanAhead => 'Rancang lebih awal';

  @override
  String get trackComfortRoute => 'Laluan selesa';

  @override
  String get trackEfficiencyRoute => 'Laluan cekap';

  @override
  String trackCrowdShort(String label) {
    return 'Kesesakan: $label';
  }

  @override
  String get trackLocatingTrainPath => 'Menjejak laluan tren';

  @override
  String trackRemaining(String distance) {
    return 'Baki: $distance';
  }

  @override
  String get trackCalculatingEta => 'Mengira ETA';

  @override
  String trackJourney(String duration) {
    return 'Perjalanan: $duration';
  }

  @override
  String trackOriginDestination(String origin, String destination) {
    return '$origin -> $destination';
  }

  @override
  String get stationsTitle => 'Atlas Stesen';

  @override
  String get stationsNearestTooltip => 'Terdekat';

  @override
  String get stationsSearchHint => 'Cari mengikut stesen, laluan atau kod';

  @override
  String get stationsClearSearch => 'Kosongkan carian';

  @override
  String get stationsLoadFailed => 'Gagal memuatkan stesen daripada Supabase';

  @override
  String get stationsEmptyTable =>
      'Bersambung, tetapi jadual train_stops_kl mempunyai 0 baris.';

  @override
  String get stationsNoMatch => 'Tiada stesen sepadan dengan carian anda.';

  @override
  String get stationsLineColors => 'Warna Laluan';

  @override
  String get stationsArrivalsButton => 'Ketibaan';

  @override
  String get stationsUnnamedStation => 'Stesen Tanpa Nama';

  @override
  String get stationsUnknownCrowdLevel => 'Tahap kesesakan tidak diketahui';

  @override
  String get stationsUnknown => 'Tidak diketahui';

  @override
  String get stationsLocationServicesDisabled =>
      'Perkhidmatan lokasi dilumpuhkan.';

  @override
  String get stationsLocationPermissionDenied => 'Kebenaran lokasi ditolak.';

  @override
  String get stationsLocationPermissionDeniedForever =>
      'Kebenaran lokasi ditolak selamanya. Hidupkan dalam tetapan.';

  @override
  String get stationsNoValidCoordinates =>
      'Tiada stop_lat/stop_lon yang sah ditemui untuk mengira jarak.';

  @override
  String stationsNearestMessage(
      String station, String distance, String lat, String lon) {
    return 'Terdekat: $station ($distance) pada $lat, $lon';
  }

  @override
  String stationsLocationFailed(String error) {
    return 'Gagal mendapatkan lokasi: $error';
  }

  @override
  String get stationsMissingStopId => 'Stesen dipilih tiada stop_id.';

  @override
  String get stationsNearestOriginFailed =>
      'Tidak dapat menentukan stesen asal terdekat.';

  @override
  String get stationsAlreadyAtStation =>
      'Anda sudah paling dekat dengan stesen ini.';

  @override
  String stationsNoRouteFoundFromTo(String origin, String destination) {
    return 'Tiada laluan ditemui dari $origin ke $destination.';
  }

  @override
  String get stationsNoOfflineRouteCache =>
      'Tiada cache laluan luar talian. Pergi dalam talian sekali untuk menyegerakkan route_connections.';

  @override
  String get stationsWalkHiddenFarFromStations =>
      'Lokasi semasa jauh daripada stesen yang disokong. Jarak berjalan disembunyikan daripada ETA.';

  @override
  String stationsPlanRouteFailed(String error) {
    return 'Gagal merancang laluan: $error';
  }

  @override
  String get stationsSelectedTimeInPast =>
      'Masa yang dipilih sudah berlalu. Menggunakan masa semasa.';

  @override
  String get stationsWhenDepartTitle => 'Bila anda ingin bertolak?';

  @override
  String get stationsChooseDepartSubtitle =>
      'Pilih sekarang atau pilih tarikh dan masa tertentu.';

  @override
  String get stationsLeaveNowButton => 'Bertolak Sekarang';

  @override
  String get stationsChooseDateTimeButton => 'Pilih Tarikh & Masa';

  @override
  String get stationsRouteSourceDisruptionLocal =>
      'Laluan semula peka gangguan (tempatan)';

  @override
  String get stationsRouteSourceRpcAlerts =>
      'Supabase RPC (makluman perkhidmatan aktif)';

  @override
  String get stationsRouteSourceRpc => 'Supabase RPC';

  @override
  String get stationsRouteSourceDisruptionGraph => 'Graf laluan peka gangguan';

  @override
  String get stationsRouteSourceGraphCache =>
      'Cache graf laluan Supabase (RPC tidak tersedia)';

  @override
  String get stationsDisruptionKjTitle =>
      'Kawalan kesesakan puncak di Laluan Kelana Jaya';

  @override
  String get stationsDisruptionKjDetail =>
      'Jangkakan masa berhenti lebih lama semasa menaiki pada waktu puncak.';

  @override
  String get stationsDisruptionAgTitle => 'Kesesakan platform di Laluan Ampang';

  @override
  String get stationsDisruptionAgDetail =>
      'Kesesakan tengah hari mungkin melambatkan menaiki dan pertukaran.';

  @override
  String get stationsDisruptionMrTitle => 'Kekerapan Monorail dikurangkan';

  @override
  String get stationsDisruptionMrDetail =>
      'Selang ketibaan lewat malam lebih panjang daripada biasa.';

  @override
  String get stationsMissingGtfsStopId =>
      'Stesen dipilih tiada id hentian GTFS.';

  @override
  String get stationsNoCodeForReport =>
      'Tiada kod stesen ditemui untuk laporan.';

  @override
  String stationsTooFarFromStation(int distance) {
    return 'Anda ${distance}m dari stesen ini. Sila bergerak dalam lingkungan 500m untuk laporan yang tepat.';
  }

  @override
  String get stationsEnableLocationToReport =>
      'Hidupkan lokasi untuk mengesahkan jarak sebelum melaporkan tahap kesesakan.';

  @override
  String get stationsReportCrowdLevel => 'Laporkan Tahap Kesesakan';

  @override
  String get stationsStationCodeLabel => 'Kod Stesen';

  @override
  String get stationsHowCrowdedNow => 'Sesak mana sekarang?';

  @override
  String stationsCrowdLevelOption(int level, String label) {
    return 'L$level $label';
  }

  @override
  String get stationsMoveCloser => 'Bergerak Lebih Dekat untuk Hantar';

  @override
  String get stationsSubmitReport => 'Hantar Laporan';

  @override
  String stationsReportSubmitted(String stopId) {
    return 'Terima kasih. Laporan kesesakan dihantar untuk $stopId.';
  }

  @override
  String stationsReportSubmitFailed(String error) {
    return 'Gagal menghantar laporan: $error';
  }

  @override
  String get stationsSuggestedRoute => 'Laluan Dicadangkan';

  @override
  String stationsRouteSummary(String originName, String originStopId,
      String destinationName, String destinationStopId) {
    return '$originName ($originStopId) -> $destinationName ($destinationStopId)';
  }

  @override
  String stationsDepartAt(String time) {
    return 'Bertolak: $time';
  }

  @override
  String stationsArriveAt(String time) {
    return 'Tiba: $time';
  }

  @override
  String stationsBaseEta(String duration) {
    return 'ETA asas ~ $duration';
  }

  @override
  String stationsCrowdEta(String duration) {
    return 'ETA kesesakan ~ $duration';
  }

  @override
  String stationsForecastConfidenceChip(String percent) {
    return 'Keyakinan ramalan $percent';
  }

  @override
  String stationsTripCrowd(String label) {
    return 'Kesesakan Perjalanan: $label';
  }

  @override
  String stationsStopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hentian',
      one: '1 hentian',
    );
    return '$_temp0';
  }

  @override
  String get stationsReroutedAroundDisruption =>
      'Laluan dialihkan mengelilingi gangguan';

  @override
  String stationsRouteSource(String source) {
    return 'Sumber: $source';
  }

  @override
  String stationsServiceAlerts(String alerts) {
    return 'Makluman perkhidmatan: $alerts';
  }

  @override
  String stationsWalkToOrigin(String distance) {
    return 'Berjalan ke stesen asal: $distance';
  }

  @override
  String get stationsNoRouteSegments => 'Tiada segmen laluan tersedia.';

  @override
  String stationsSegmentTimeRange(String depart, String arrive, String label) {
    return '$depart hingga $arrive - $label';
  }

  @override
  String stationsForecastConfidence(String percent) {
    return 'Keyakinan ramalan: $percent';
  }

  @override
  String stationsBoardingTip(String tip) {
    return 'Tip gerabak/platform: $tip';
  }

  @override
  String stationsServiceAlert(String note) {
    return 'Makluman perkhidmatan: $note';
  }

  @override
  String stationsIncludesWaitingTime(int minutes) {
    return 'Termasuk lebih kurang $minutes minit masa menunggu';
  }

  @override
  String get stationsForecastReasonClosed =>
      'Perkhidmatan tren kini di luar waktu operasi.';

  @override
  String get stationsForecastReasonRecentReports => 'laporan penumpang terkini';

  @override
  String get stationsForecastReasonHourlyForecast =>
      'ramalan penumpang setiap jam';

  @override
  String get stationsForecastReasonSimulation => 'sandaran simulasi 10 minit';

  @override
  String get stationsForecastReasonOfflineFallback =>
      'anggaran sandaran luar talian';

  @override
  String get stationsForecastReasonTransferWait =>
      'masa menunggu pertukaran disertakan';

  @override
  String get stationsForecastReasonPeakLoad =>
      'keadaan beban puncak mungkin berlaku';

  @override
  String get stationsForecastReasonStandingDemand =>
      'permintaan berdiri mungkin berlaku';

  @override
  String stationsBoardingTipTransfer(String station) {
    return 'Ikut papan tanda pertukaran dengan segera di $station.';
  }

  @override
  String stationsBoardingTipMiddleRear(String station) {
    return 'Naiki gerabak tengah-belakang untuk pertukaran lebih pantas di $station.';
  }

  @override
  String stationsBoardingTipNearDoors(String station) {
    return 'Naiki berhampiran pintu untuk keluar lebih pantas di $station.';
  }

  @override
  String stationsBoardingTipPlatformSigns(String station) {
    return 'Ikut papan tanda platform menuju perkhidmatan arah $station.';
  }

  @override
  String stationsSegmentTransfer(
      String from, String to, String base, String forecast) {
    return 'Pertukaran dari $from ke $to ($base asas, ~$forecast ramalan)';
  }

  @override
  String stationsSegmentRide(
      String route, String from, String to, String base, String forecast) {
    return 'Naik $route dari $from ke $to ($base asas, ~$forecast ramalan)';
  }

  @override
  String stationsFareTotal(String amount) {
    return 'Tambang RM $amount';
  }

  @override
  String stationsFareTicketCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tiket',
      one: '1 tiket',
    );
    return '$_temp0';
  }

  @override
  String stationsSegmentFare(String amount) {
    return 'RM $amount';
  }

  @override
  String get arrivalsNextTrain => 'TREN SETERUSNYA';

  @override
  String get arrivalsSignalLost => 'ISYARAT HILANG — KETUK UNTUK CUBA LAGI';

  @override
  String get arrivalsNoScheduledTrains => 'TIADA TREN BERJADUAL';

  @override
  String get arrivalsOfflineStaticSchedule => 'LUAR TALIAN — JADUAL STATIK';

  @override
  String get arrivalsGtfsStaticSchedule => 'JADUAL STATIK GTFS';

  @override
  String arrivalsToDestination(String destination) {
    return 'KE $destination';
  }

  @override
  String get arrivalsArriving => 'TIBA';

  @override
  String arrivalsMinutesShort(int minutes) {
    return '$minutes minit';
  }

  @override
  String get crowdBoardTitle => 'Denyut Kesesakan';

  @override
  String get crowdBoardSearchHint => 'Cari nama stesen';

  @override
  String get crowdBoardLoading => 'Memuatkan…';

  @override
  String get crowdBoardEmpty => 'Tiada data kesesakan stesen tersedia lagi.';

  @override
  String get crowdBoardFilterAll => 'Semua';

  @override
  String crowdBoardLevelClosed(String label) {
    return '$label · Tutup';
  }

  @override
  String get forecastTitle => 'Tinjauan Kesesakan';

  @override
  String get forecastNoStations => 'Tiada stesen ditemui.';

  @override
  String get forecastStationLabel => 'Stesen';

  @override
  String forecastLoadFailed(String error) {
    return 'Gagal memuatkan ramalan kesesakan: $error';
  }

  @override
  String get forecastEmpty => 'Belum ada ramalan untuk stesen ini.';

  @override
  String get forecastClosingHoursBody =>
      'Perkhidmatan tren kini ditutup. Ramalan bersambung semula dari 6:00 AM.';

  @override
  String get forecastLevel1Subtitle =>
      'Hampir kosong dengan tempat duduk yang banyak';

  @override
  String get forecastLevel2Subtitle =>
      'Perjalanan selesa dengan ruang yang lapang';

  @override
  String get forecastLevel3Subtitle =>
      'Kesesakan sederhana dengan permintaan berdiri yang biasa';

  @override
  String get forecastLevel4Subtitle =>
      'Kesesakan tinggi dengan kemungkinan menaiki lebih perlahan';

  @override
  String get forecastLevel5Subtitle =>
      'Keadaan sesak di seluruh platform dan gerabak';

  @override
  String get forecastUnknownLevelSubtitle => 'Tiada tahap kesesakan yang sah';

  @override
  String get forecastExplanationClosed =>
      'Perkhidmatan tren di luar waktu operasi. Stesen ditunjukkan tidak tersedia sehingga 6:00 AM.';

  @override
  String get forecastExplanationRecentReports =>
      'berdasarkan laporan penumpang terkini';

  @override
  String get forecastExplanationHourlyForecast =>
      'berdasarkan ramalan penumpang setiap jam';

  @override
  String get forecastExplanationSimulation =>
      'menggunakan sandaran simulasi 10 minit';

  @override
  String get forecastExplanationOfflineFallback =>
      'menggunakan anggaran sandaran luar talian';

  @override
  String get forecastReasonVeryLowOccupancy =>
      'jangkaan kesesakan sangat rendah';

  @override
  String get forecastReasonComfortableSpace => 'ruang selesa masih tersedia';

  @override
  String get forecastReasonModerateStanding =>
      'permintaan berdiri sederhana mungkin berlaku';

  @override
  String forecastLevelLabel(int level) {
    return 'Tahap $level';
  }

  @override
  String forecastLevelClosed(int level) {
    return 'Tahap $level · Tutup';
  }

  @override
  String forecastUpdated(String time) {
    return 'Dikemas kini: $time';
  }
}
