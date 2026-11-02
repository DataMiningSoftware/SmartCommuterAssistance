// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Smart Commuter Assistant+';

  @override
  String get navHome => 'Home';

  @override
  String get navMap => 'Map';

  @override
  String get navTrack => 'Track';

  @override
  String get navRace => 'Race';

  @override
  String get navProfile => 'Profile';

  @override
  String closingIn(String time) {
    return 'Trains closing in $time';
  }

  @override
  String get dataLive => 'LIVE';

  @override
  String get dataOffline => 'OFFLINE';

  @override
  String get crowdLevelEmpty => 'Empty';

  @override
  String get crowdLevelLight => 'Light';

  @override
  String get crowdLevelModerate => 'Moderate';

  @override
  String get crowdLevelHeavy => 'Heavy';

  @override
  String get crowdLevelCrowded => 'Crowded';

  @override
  String get crowdLevelUnknown => 'Unknown';

  @override
  String get mapSubtitle => 'Geographic and schematic views';

  @override
  String get mapGeographic => 'Geographic';

  @override
  String get mapTransitMap => 'Transit map';

  @override
  String get mapStationHint => 'Station';

  @override
  String mapLoadFailed(String error) {
    return 'Failed to load map data: $error';
  }

  @override
  String get mapTapAnotherStation =>
      'Tap another station to plan a route from here.';

  @override
  String get mapFindingRoute => 'Finding the best route...';

  @override
  String mapRouteSummary(String duration, String transfers, String crowd) {
    return '$duration · $transfers · $crowd crowd';
  }

  @override
  String get mapChooseDifferent => 'Choose different';

  @override
  String get mapStartJourney => 'Start journey';

  @override
  String get mapJourneyStarted =>
      'Journey started — tracking on the Track tab.';

  @override
  String get mapSchematicA11yLabel =>
      'Transit map. Tap a station to select it.';

  @override
  String get mapZoomIn => 'Zoom in';

  @override
  String get mapZoomOut => 'Zoom out';

  @override
  String get dataSourceScheduled => 'Scheduled';

  @override
  String get dataSourceRiderReport => 'Rider report';

  @override
  String get dataSourceBlended => 'Blended';

  @override
  String get dataSourceEstimated => 'Estimated';

  @override
  String get dataSourceClosed => 'Closed';

  @override
  String get dataSourceFallback => 'Fallback';

  @override
  String get dataSourceUnknown => 'Unknown';

  @override
  String get connectivityConnected => 'You are connected';

  @override
  String get connectivityDisconnected => 'Disconnected';

  @override
  String get offlineTitle => 'You\'re offline';

  @override
  String get offlineBody =>
      'Some features need a connection. Cached stations, saved routes and local crowd estimates still work.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get continueOffline => 'Continue offline';

  @override
  String get configurationRequired => 'Configuration Required';

  @override
  String get retry => 'Retry';

  @override
  String get preparingData => 'Preparing your commute data...';

  @override
  String startupFailed(String error) {
    return 'Startup failed.\n\n$error';
  }

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystemOption => 'System default';

  @override
  String get languageEnglishOption => 'English';

  @override
  String get languageMalayOption => 'Bahasa Melayu';

  @override
  String get profileCommuter => 'Commuter';

  @override
  String get profileUserFallback => 'User';

  @override
  String get profileNoAccount => 'No account needed — reports are anonymous';

  @override
  String get profileEditTooltip => 'Edit profile';

  @override
  String get preferencesTitle => 'Preferences';

  @override
  String get pushNotificationsTitle => 'Push Notifications';

  @override
  String get pushNotificationsSubtitle => 'Delay and route alerts';

  @override
  String get offlineModeTitle => 'Offline Mode';

  @override
  String get offlineModeSubtitle => 'Cache schedules for weak coverage';

  @override
  String get locationSharingTitle => 'Location Sharing';

  @override
  String get locationSharingSubtitle =>
      'Used for nearby stations; sent rounded to ~1 km';

  @override
  String get mlConsentTitle => 'Improve predictions with my trip data';

  @override
  String get mlConsentSubtitle =>
      'Optional. Uses your reports and trip times for model training';

  @override
  String get accessibilityTitle => 'Accessibility';

  @override
  String get accessibilitySubtitle => 'Larger labels and stronger contrast';

  @override
  String get darkModeTitle => 'Dark Mode';

  @override
  String get darkModeSubtitle => 'Enable dark theme for the app';

  @override
  String get dataAttributionsTitle => 'Data Attributions';

  @override
  String get mapTilesTitle => 'Map tiles';

  @override
  String get mapTilesSource => '© CartoDB';

  @override
  String get weatherTitle => 'Weather';

  @override
  String get weatherSource => 'Weather data by Open-Meteo.com';

  @override
  String get transitScheduleTitle => 'Transit schedule';

  @override
  String get transitScheduleSource => '© Prasarana Malaysia via data.gov.my';

  @override
  String get quickActionsTitle => 'Quick Actions';

  @override
  String get routeBuilderTitle => 'Route Builder';

  @override
  String get friendsTitle => 'Friends';

  @override
  String get learnTheRailsTitle => 'Learn the Rails';

  @override
  String get favoriteRoutesTitle => 'Favorite Routes';

  @override
  String get travelHistoryTitle => 'Travel History';

  @override
  String get testNotificationTitle => 'Test notification';

  @override
  String get testNotificationBody => 'This is a test notification. 🚆';

  @override
  String get helpSupportTitle => 'Help & Support';

  @override
  String get aboutTitle => 'About';

  @override
  String get privacyPolicyTitle => 'Privacy Policy';

  @override
  String get logoutButton => 'Logout';

  @override
  String get deleteMyDataButton => 'Delete my data';

  @override
  String get deleteAccountButton => 'Delete Account';

  @override
  String get profileDeleteDataDialogTitle => 'Delete my data?';

  @override
  String get profileDeleteAccountDialogTitle => 'Delete account?';

  @override
  String get profileDeleteDataDialogBody =>
      'This permanently removes your anonymous device profile, account and trip feedback. Your contributed reports are unlinked and anonymised. This cannot be undone.';

  @override
  String get profileDeleteAccountDialogBody =>
      'This permanently deletes your account, profile, and travel history. Your contributed reports are unlinked and anonymised. This cannot be undone.';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get deleteButton => 'Delete';

  @override
  String get accountDeleted => 'Account deleted.';

  @override
  String get deleteAccountFailed =>
      'Could not delete account automatically. Please use the account deletion link in the privacy policy.';

  @override
  String get editProfileTitle => 'Edit Profile';

  @override
  String get handleLabel => 'Handle';

  @override
  String get displayNameLabel => 'Display name';

  @override
  String get bioLabel => 'Bio';

  @override
  String get avatarColorLabel => 'Avatar color (hex, optional)';

  @override
  String get homeStationLabel => 'Home station ID (optional)';

  @override
  String get favoriteLineLabel => 'Favorite line (optional)';

  @override
  String get allowFindByHandle => 'Allow others to find me by handle';

  @override
  String get saveButton => 'Save';

  @override
  String get aboutDialogTitle => 'About Smart Commuter Assistant+';

  @override
  String aboutDialogBody(String version) {
    return 'Smart Commuter Assistant+ v$version\n\nDynamic Navigation & Occupancy Computations.\n\nAn intelligent companion for Malaysian public transport.\n\nAn independent, unofficial app — not affiliated with Rapid KL, Prasarana Malaysia, or KTMB.';
  }

  @override
  String get okButton => 'OK';

  @override
  String get railIndependenceTitle => 'Your Rail Independence';

  @override
  String railIndependenceBody(int stations, int accuracy) {
    String _temp0 = intl.Intl.pluralLogic(
      stations,
      locale: localeName,
      other: 'stations',
      one: 'station',
    );
    return 'You know $stations $_temp0 and answer $accuracy% of trivia correctly. Keep going — the goal is to not need us.';
  }

  @override
  String get locationServicesOff =>
      'Turn on Location Services to use nearby stations.';

  @override
  String get locationPermissionDenied =>
      'Location permission denied in system settings.';

  @override
  String get loginWelcome => 'Welcome back';

  @override
  String get loginSubtitle =>
      'Login to view forecasts, routes, and your travel history.';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get emailInvalid => 'Enter a valid email';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get passwordMinLength => 'Use at least 6 characters';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get nameRequired => 'Name is required';

  @override
  String get fullNameLabel => 'Full name';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get loginButton => 'Login';

  @override
  String get signInWithGoogleButton => 'Sign in with Google';

  @override
  String get guestModeEnabled =>
      'Guest mode enabled. You can continue without an account.';

  @override
  String get guestModeFailed =>
      'Unable to enter guest mode right now. Please try again.';

  @override
  String get continueAsGuestButton => 'Continue as guest';

  @override
  String get createAccountButton => 'Create account';

  @override
  String get signInWithPhoneButton => 'Sign in with phone';

  @override
  String get signUpTitle => 'Create Your Pass';

  @override
  String get creatingAccount => 'Creating…';

  @override
  String get accountCreatedVerify =>
      'Account created! Check your email to verify it, then log in.';

  @override
  String get phoneNumberLabel => 'Phone number';

  @override
  String get phoneNumberHint => '+60 12-345 6789';

  @override
  String get verificationCodeLabel => 'Verification code';

  @override
  String get pleaseWait => 'Please wait…';

  @override
  String get verifyCodeButton => 'Verify code';

  @override
  String get sendCodeButton => 'Send code';

  @override
  String get otpInfo =>
      'A one-time code will be sent by SMS. Requires the Phone provider to be enabled in Supabase.';

  @override
  String get supportContactTitle => 'Email the developer';

  @override
  String get supportContactBody =>
      'Questions, bug reports, or feature ideas? We usually reply within a few days.';

  @override
  String get supportSendEmailButton => 'Send email';

  @override
  String get supportCopyEmailButton => 'Copy email address';

  @override
  String get supportEmailCopied => 'Email address copied';

  @override
  String get supportNoMailApp => 'No email app found — address copied instead';

  @override
  String get supportFaqTitle => 'Frequently asked questions';

  @override
  String get supportFaqOfflineQuestion =>
      'Why do some features stop working offline?';

  @override
  String get supportFaqOfflineAnswer =>
      'Live arrivals, crowd forecasts and route planning need a connection. Stations, saved routes and the last cached forecasts keep working in offline mode.';

  @override
  String get supportFaqCrowdQuestion => 'Where do crowd forecasts come from?';

  @override
  String get supportFaqCrowdAnswer =>
      'Hourly forecasts are trained on rider reports and blended with recent community reports. Verified reports from different riders carry more weight.';

  @override
  String get supportFaqDelayQuestion => 'How do delay reports work?';

  @override
  String get supportFaqDelayAnswer =>
      'When at least 3 riders report a delay on the same line and direction within 20 minutes, other riders see a delay signal and their ETA is adjusted automatically.';

  @override
  String get supportFaqPrivacyQuestion => 'What happens to my data?';

  @override
  String get supportFaqPrivacyAnswer =>
      'The app works anonymously without an account. Location stays on your device except rounded (~1 km) crowd reports you choose to send. You can delete everything from Profile.';

  @override
  String get supportFaqEtaQuestion => 'How accurate are the ETAs?';

  @override
  String get supportFaqEtaAnswer =>
      'ETAs are pinned when you reach your origin station and count down steadily. They adjust for delay and crowd reports, and improve over time as trip feedback is collected.';

  @override
  String get supportLinksTitle => 'More';

  @override
  String get supportDeleteDataLink => 'Delete your data (web)';

  @override
  String get supportIssuesLink => 'Report an issue on GitHub';

  @override
  String supportEmailSubject(String version) {
    return '[Smart Commuter Assistant+] Support — v$version';
  }

  @override
  String supportEmailBody(String version, String build, String platform,
      String locale, String connection) {
    return 'Describe your issue here.\n\n---\nApp: Smart Commuter Assistant+ $version ($build)\nPlatform: $platform\nLocale: $locale\nConnection: $connection\n---';
  }

  @override
  String homeStationUnavailableClosingHours(String station) {
    return '$station is unavailable during closing hours for the selected departure time.';
  }

  @override
  String get homeLocationRequired =>
      'Location is required before starting a trip.';

  @override
  String get homeNearestStationUnavailable =>
      'Could not determine your nearest station yet.';

  @override
  String homeNoRouteFound(String station) {
    return 'No route found for $station.';
  }

  @override
  String homePrepareTripFailed(String error) {
    return 'Could not prepare trip: $error';
  }

  @override
  String get homeRouteCrowdedTitle => 'Looks like your route is crowded.';

  @override
  String homeCalmerTripAvailable(String destination) {
    return 'A calmer trip to $destination is available, but it may take longer.';
  }

  @override
  String get homeEfficientRoute => 'Efficient route';

  @override
  String get homeFastestOptionNow => 'Fastest option right now';

  @override
  String get homeKeepThisRoute => 'Keep this route';

  @override
  String get homeRelaxedRoute => 'Relaxed route';

  @override
  String get homeCalmerRideDetour => 'Calmer ride with a small detour';

  @override
  String get homeTakeRelaxedRoute => 'Take a more relaxed route';

  @override
  String get homeLocationPrivacyTitle => 'Location Privacy';

  @override
  String get homeLocationPrivacyBody =>
      'Your location is used to find nearby stations and provide arrival estimates. Coordinates are rounded to ~1 km precision before being sent to our servers. Your exact location is never stored or shared.\n\nYou can change this later in Profile settings.';

  @override
  String get homeSkip => 'Skip';

  @override
  String get homeAllow => 'Allow';

  @override
  String homeCrowdLevelsLower(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count crowd levels lower',
      one: '1 crowd level lower',
    );
    return '$_temp0';
  }

  @override
  String homeCrowdLevelsHigher(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count crowd levels higher',
      one: '1 crowd level higher',
    );
    return '$_temp0';
  }

  @override
  String get homeFastest => 'Fastest';

  @override
  String get homeNoTimePenalty => 'No time penalty';

  @override
  String homePlusMinutes(int minutes) {
    return '+$minutes min';
  }

  @override
  String get homeDirectRide => 'Direct ride';

  @override
  String homeTransferCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transfers',
      one: '1 transfer',
    );
    return '$_temp0';
  }

  @override
  String get homeSubtitle => 'Home base';

  @override
  String get homeHeroTitle => 'Ride smart, skip the squeeze.';

  @override
  String get homeHeroSubtitle =>
      'Live crowd-aware routing, trip tracking, and route glow in one place.';

  @override
  String get homeAllStations => 'All Stations';

  @override
  String get homeAllStationsSubtitle => 'Browse lines and interchanges';

  @override
  String get homeTrackRoute => 'Track Route';

  @override
  String get homeResumeTrip => 'Resume Trip';

  @override
  String get homeStartTripHint => 'Start a trip to unlock tracking';

  @override
  String homeTripDirection(String origin, String destination) {
    return '$origin to $destination';
  }

  @override
  String get homeRouteModeAuto => 'Auto';

  @override
  String get homeRouteModeEfficient => 'Efficient';

  @override
  String get homeRouteModeRelaxed => 'Relaxed';

  @override
  String get homeRouteModeAutoHelper =>
      'Compare efficient and relaxed routes, then ask only when the calmer route is worth it.';

  @override
  String get homeRouteModeEfficientHelper => 'Always keep the fastest route.';

  @override
  String get homeRouteModeComfortHelper =>
      'Prefer lower crowd even if the trip takes a little longer.';

  @override
  String get homePickNextStop => 'Pick Your Next Stop';

  @override
  String get homeSearchDestinationHint =>
      'Search a destination, set your routing style, and preview crowd before you leave.';

  @override
  String get homeRouteStyle => 'Route style';

  @override
  String get homeLoadingStations => 'Loading stations…';

  @override
  String homeLoadStationsFailed(String error) {
    return 'Failed to load stations: $error';
  }

  @override
  String get homeNoStationNames =>
      'No station names available yet. Showing a local sample list instead.';

  @override
  String get homeSearchTrainStation => 'Search train station';

  @override
  String get homeClosingHours => 'Closing hours';

  @override
  String get homePlanAhead => 'Plan Ahead';

  @override
  String get homeLiveMapUnavailable => 'Live map unavailable';

  @override
  String get homeEtaSyncing => 'ETA syncing';

  @override
  String get homeArrivingNow => 'Arriving now';

  @override
  String homeArriveBy(String time) {
    return 'Arrive by $time';
  }

  @override
  String get homeLiveTrip => 'Live Trip';

  @override
  String get homeViewMap => 'View map';

  @override
  String get homeRelaxedRoutingActive => 'Relaxed routing is active.';

  @override
  String get homeLiveTrackingReady => 'Live tracking is ready.';

  @override
  String get homeYouAreHere => 'You are here';

  @override
  String homeTripEtaTo(int minutes, String destination) {
    return '$minutes min to $destination';
  }

  @override
  String get homeCrowdLevelPrefix => 'Crowd level: ';

  @override
  String get homeOpenTracking => 'Open tracking';

  @override
  String get homeStationCrowdBoard => 'Station Crowd Board';

  @override
  String get homeNearestStationSubtitle =>
      'Showing the nearest station to your current location.';

  @override
  String get homeViewAll => 'View all';

  @override
  String get homeRefreshNearbyStations => 'Refresh nearby stations';

  @override
  String homeLoadCrowdBoardFailed(String error) {
    return 'Failed to load crowd board: $error';
  }

  @override
  String get homeLocationSyncing =>
      'Location is still syncing. Pull to refresh or try again in a moment.';

  @override
  String homeMetersAway(String distance) {
    return '$distance m away';
  }

  @override
  String get homeReportCrowded => 'Report crowded';

  @override
  String homeEtaLabel(String duration) {
    return 'ETA $duration';
  }

  @override
  String homeDurationMinutesShort(int minutes) {
    return '${minutes}m';
  }

  @override
  String homeDurationHoursShort(int hours) {
    return '${hours}h';
  }

  @override
  String homeDurationHoursMinutesShort(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String get homeRoutePending => 'Route pending';

  @override
  String get trackKeepCrowdedRoute => 'Keep with crowded route';

  @override
  String get trackPlanYourTrip => 'Plan Your Trip';

  @override
  String get trackSelectOriginDestination =>
      'Select origin and destination stations.';

  @override
  String get trackFromLabel => 'From';

  @override
  String get trackToLabel => 'To';

  @override
  String get trackSetArrivalTime => 'Set arrival time';

  @override
  String get trackWhenArrive => 'When do you want to arrive?';

  @override
  String get trackTargetArrivalHint =>
      'Set your target arrival time and we\'ll calculate when to leave.';

  @override
  String get trackCalculate => 'Calculate';

  @override
  String get trackCalculatingSchedule => 'Calculating schedule...';

  @override
  String trackNoRouteFoundTo(String station) {
    return 'No route found to $station.';
  }

  @override
  String trackPlanAheadFailed(String error) {
    return 'Could not plan ahead: $error';
  }

  @override
  String get trackTripPlan => 'Trip Plan';

  @override
  String get trackLeaveBy => 'Leave by';

  @override
  String trackWalkTo(String station) {
    return 'Walk to $station';
  }

  @override
  String trackDurationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String trackVia(String routes) {
    return 'Via $routes';
  }

  @override
  String trackArriveAt(String station) {
    return 'Arrive at $station';
  }

  @override
  String trackEstimatedTotal(int minutes) {
    return 'Estimated total: $minutes min';
  }

  @override
  String get trackStartThisTripNow => 'Start this trip now';

  @override
  String trackStationUnavailableClosingHours(String station) {
    return '$station is unavailable during closing hours.';
  }

  @override
  String get trackEnableLocationServices =>
      'Enable location services before starting a trip.';

  @override
  String get trackLocationPermissionRequired =>
      'Location permission is required to start a trip.';

  @override
  String trackChooseDestinationBeyond(String station) {
    return 'Choose a destination beyond $station.';
  }

  @override
  String trackStartTripFailed(String error) {
    return 'Could not start trip: $error';
  }

  @override
  String trackSwitchDestinationFrom(String station) {
    return 'Switch destination from $station';
  }

  @override
  String get trackSwitchDestinationHint =>
      'Pick a new target station and the route will restart from where you are now.';

  @override
  String get trackSearchStationOrCode => 'Search station or code';

  @override
  String get trackAreYouOkay => 'Are you okay?';

  @override
  String get trackInactivityBody =>
      'You haven\'t moved in a while. Is everything alright?';

  @override
  String get trackImFine => 'I\'m fine';

  @override
  String get trackCallEmergencyContact => 'Call emergency contact';

  @override
  String get trackCancelTrip => 'Cancel trip';

  @override
  String get trackEmergencyDialer =>
      'Emergency contact dialer would open here.';

  @override
  String get trackRouteRecalculated => 'Route recalculated';

  @override
  String get trackDeviatedFromRoute =>
      'You\'ve deviated from your route a few times.';

  @override
  String get trackPickNewDestination =>
      'Would you like to pick a new destination instead?';

  @override
  String get trackContinueToDestination => 'Continue to current destination';

  @override
  String get trackChooseNewDestination => 'Choose a new destination';

  @override
  String get trackLocatingTrain => 'Locating train';

  @override
  String trackChangeLineAt(String station) {
    return 'Change line at $station';
  }

  @override
  String trackSwitchToLine(String routeId) {
    return 'Switch to the $routeId line after this station.';
  }

  @override
  String trackReachedDestination(String destination) {
    return 'You have reached $destination';
  }

  @override
  String get trackTripEnded => 'Your trip has ended.';

  @override
  String trackRidersReportDelays(int count, String route, int minutes) {
    return '$count riders report delays on $route · +$minutes min';
  }

  @override
  String get trackDelayReportFailed =>
      'Could not submit the delay report. Please try again.';

  @override
  String trackCrowdedReported(String stopId) {
    return 'Crowded train reported for $stopId.';
  }

  @override
  String trackDelayReported(String stopId) {
    return 'Delay reported for $stopId.';
  }

  @override
  String trackReportSubmitFailed(String error) {
    return 'Could not submit report: $error';
  }

  @override
  String get trackCancelActiveTripTitle => 'Cancel active trip?';

  @override
  String get trackCancelActiveTripBody =>
      'This will stop live tracking and clear the saved route.';

  @override
  String get trackKeepTrip => 'Keep Trip';

  @override
  String get trackTitleLeading => 'Trip';

  @override
  String get trackTitleAccent => 'Motion';

  @override
  String get trackTitleSubtitle => 'Tracking';

  @override
  String get trackPickStationFromResults =>
      'Pick a station from the search results.';

  @override
  String get trackPreparingTimeline => 'Preparing route timeline...';

  @override
  String get trackSending => 'Sending...';

  @override
  String get trackReport => 'Report';

  @override
  String get trackSyncing => 'syncing';

  @override
  String get trackArrived => 'Arrived';

  @override
  String trackStopsRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops',
      one: '1 stop',
    );
    return '$_temp0';
  }

  @override
  String get trackTimeLeft => 'Time left';

  @override
  String get trackArriveBy => 'Arrive by';

  @override
  String trackPercent(int percent) {
    return '$percent%';
  }

  @override
  String trackPercentCompleted(int percent) {
    return '$percent% completed';
  }

  @override
  String get trackChangeDestination => 'Change destination';

  @override
  String trackChangeTo(String routeId) {
    return 'Change to $routeId';
  }

  @override
  String get trackStartStation => 'Start station';

  @override
  String get trackEndStation => 'End station';

  @override
  String trackForecast(String label) {
    return 'Forecast: $label';
  }

  @override
  String get trackCrowdedTrain => 'Crowded train';

  @override
  String get trackDelay => 'Delay';

  @override
  String get trackNoActiveTrip => 'No active trip yet.';

  @override
  String get trackNoActiveTripBody =>
      'Search for a destination here and start tracking straight from the track page.';

  @override
  String get trackStartingTrip => 'Starting trip...';

  @override
  String get trackSearch => 'Search';

  @override
  String get trackPlanAhead => 'Plan ahead';

  @override
  String get trackComfortRoute => 'Comfort route';

  @override
  String get trackEfficiencyRoute => 'Efficiency route';

  @override
  String trackCrowdShort(String label) {
    return 'Crowd: $label';
  }

  @override
  String get trackLocatingTrainPath => 'Locating train path';

  @override
  String trackRemaining(String distance) {
    return 'Remaining: $distance';
  }

  @override
  String get trackCalculatingEta => 'Calculating ETA';

  @override
  String trackJourney(String duration) {
    return 'Journey: $duration';
  }

  @override
  String trackOriginDestination(String origin, String destination) {
    return '$origin -> $destination';
  }

  @override
  String get stationsTitle => 'Station Atlas';

  @override
  String get stationsNearestTooltip => 'Nearest';

  @override
  String get stationsSearchHint => 'Search by station, line, or code';

  @override
  String get stationsClearSearch => 'Clear search';

  @override
  String get stationsLoadFailed => 'Failed to load stations from Supabase';

  @override
  String get stationsEmptyTable =>
      'Connected, but table train_stops_kl has 0 rows.';

  @override
  String get stationsNoMatch => 'No stations match your search.';

  @override
  String get stationsLineColors => 'Line Colors';

  @override
  String get stationsArrivalsButton => 'Arrivals';

  @override
  String get stationsUnnamedStation => 'Unnamed Station';

  @override
  String get stationsUnknownCrowdLevel => 'Unknown crowd level';

  @override
  String get stationsUnknown => 'Unknown';

  @override
  String get stationsLocationServicesDisabled =>
      'Location services are disabled.';

  @override
  String get stationsLocationPermissionDenied => 'Location permission denied.';

  @override
  String get stationsLocationPermissionDeniedForever =>
      'Location permission denied forever. Enable it in settings.';

  @override
  String get stationsNoValidCoordinates =>
      'No valid stop_lat/stop_lon found to calculate distance.';

  @override
  String stationsNearestMessage(
      String station, String distance, String lat, String lon) {
    return 'Nearest: $station ($distance) at $lat, $lon';
  }

  @override
  String stationsLocationFailed(String error) {
    return 'Failed to get location: $error';
  }

  @override
  String get stationsMissingStopId => 'Selected station is missing stop_id.';

  @override
  String get stationsNearestOriginFailed =>
      'Could not determine nearest origin station.';

  @override
  String get stationsAlreadyAtStation =>
      'You are already nearest to this station.';

  @override
  String stationsNoRouteFoundFromTo(String origin, String destination) {
    return 'No route found from $origin to $destination.';
  }

  @override
  String get stationsNoOfflineRouteCache =>
      'No offline route cache available. Go online once to sync route_connections.';

  @override
  String get stationsWalkHiddenFarFromStations =>
      'Current location is far from supported stations. Walk distance is hidden from ETA.';

  @override
  String stationsPlanRouteFailed(String error) {
    return 'Failed to plan route: $error';
  }

  @override
  String get stationsSelectedTimeInPast =>
      'Selected time is in the past. Using current time instead.';

  @override
  String get stationsWhenDepartTitle => 'When do you want to depart?';

  @override
  String get stationsChooseDepartSubtitle =>
      'Choose now or pick a specific date and time.';

  @override
  String get stationsLeaveNowButton => 'Leave Now';

  @override
  String get stationsChooseDateTimeButton => 'Choose Date & Time';

  @override
  String get stationsRouteSourceDisruptionLocal =>
      'Disruption-aware reroute (local)';

  @override
  String get stationsRouteSourceRpcAlerts =>
      'Supabase RPC (service alerts active)';

  @override
  String get stationsRouteSourceRpc => 'Supabase RPC';

  @override
  String get stationsRouteSourceDisruptionGraph =>
      'Disruption-aware route graph';

  @override
  String get stationsRouteSourceGraphCache =>
      'Supabase route graph cache (RPC unavailable)';

  @override
  String get stationsDisruptionKjTitle =>
      'Peak crowd control on Kelana Jaya Line';

  @override
  String get stationsDisruptionKjDetail =>
      'Expect longer dwell times during rush-hour boarding.';

  @override
  String get stationsDisruptionAgTitle => 'Platform congestion on Ampang Line';

  @override
  String get stationsDisruptionAgDetail =>
      'Midday crowding may slow boarding and transfers.';

  @override
  String get stationsDisruptionMrTitle => 'Reduced Monorail frequency';

  @override
  String get stationsDisruptionMrDetail =>
      'Late-evening headways are wider than usual.';

  @override
  String get stationsMissingGtfsStopId =>
      'Selected station is missing a GTFS stop id.';

  @override
  String get stationsNoCodeForReport => 'No station code found for reporting.';

  @override
  String stationsTooFarFromStation(int distance) {
    return 'You are ${distance}m from this station. Please move within 500m for accurate reporting.';
  }

  @override
  String get stationsEnableLocationToReport =>
      'Enable location to verify proximity before reporting crowd levels.';

  @override
  String get stationsReportCrowdLevel => 'Report Crowd Level';

  @override
  String get stationsStationCodeLabel => 'Station Code';

  @override
  String get stationsHowCrowdedNow => 'How crowded is it now?';

  @override
  String stationsCrowdLevelOption(int level, String label) {
    return 'L$level $label';
  }

  @override
  String get stationsMoveCloser => 'Move Closer to Submit';

  @override
  String get stationsSubmitReport => 'Submit Report';

  @override
  String stationsReportSubmitted(String stopId) {
    return 'Thanks. Crowd report submitted for $stopId.';
  }

  @override
  String stationsReportSubmitFailed(String error) {
    return 'Failed to submit report: $error';
  }

  @override
  String get stationsSuggestedRoute => 'Suggested Route';

  @override
  String stationsRouteSummary(String originName, String originStopId,
      String destinationName, String destinationStopId) {
    return '$originName ($originStopId) -> $destinationName ($destinationStopId)';
  }

  @override
  String stationsDepartAt(String time) {
    return 'Depart: $time';
  }

  @override
  String stationsArriveAt(String time) {
    return 'Arrive: $time';
  }

  @override
  String stationsBaseEta(String duration) {
    return 'Base ETA ~ $duration';
  }

  @override
  String stationsCrowdEta(String duration) {
    return 'Crowd ETA ~ $duration';
  }

  @override
  String stationsForecastConfidenceChip(String percent) {
    return 'Forecast confidence $percent';
  }

  @override
  String stationsTripCrowd(String label) {
    return 'Trip Crowd: $label';
  }

  @override
  String stationsStopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stops',
      one: '1 stop',
    );
    return '$_temp0';
  }

  @override
  String get stationsReroutedAroundDisruption => 'Rerouted around disruption';

  @override
  String stationsRouteSource(String source) {
    return 'Source: $source';
  }

  @override
  String stationsServiceAlerts(String alerts) {
    return 'Service alerts: $alerts';
  }

  @override
  String stationsWalkToOrigin(String distance) {
    return 'Walk to origin: $distance';
  }

  @override
  String get stationsNoRouteSegments => 'No route segments available.';

  @override
  String stationsSegmentTimeRange(String depart, String arrive, String label) {
    return '$depart to $arrive - $label';
  }

  @override
  String stationsForecastConfidence(String percent) {
    return 'Forecast confidence: $percent';
  }

  @override
  String stationsBoardingTip(String tip) {
    return 'Coach/platform tip: $tip';
  }

  @override
  String stationsServiceAlert(String note) {
    return 'Service alert: $note';
  }

  @override
  String stationsIncludesWaitingTime(int minutes) {
    return 'Includes approx. $minutes min waiting time';
  }

  @override
  String get stationsForecastReasonClosed =>
      'Train service is currently outside operating hours.';

  @override
  String get stationsForecastReasonRecentReports => 'recent rider reports';

  @override
  String get stationsForecastReasonHourlyForecast =>
      'hourly ridership forecast';

  @override
  String get stationsForecastReasonSimulation =>
      '10-minute simulation fallback';

  @override
  String get stationsForecastReasonOfflineFallback =>
      'offline fallback estimate';

  @override
  String get stationsForecastReasonTransferWait => 'transfer wait included';

  @override
  String get stationsForecastReasonPeakLoad => 'peak-load conditions likely';

  @override
  String get stationsForecastReasonStandingDemand => 'standing demand likely';

  @override
  String stationsBoardingTipTransfer(String station) {
    return 'Follow interchange signs promptly at $station.';
  }

  @override
  String stationsBoardingTipMiddleRear(String station) {
    return 'Board middle-rear coach for a faster transfer at $station.';
  }

  @override
  String stationsBoardingTipNearDoors(String station) {
    return 'Board near the doors for a quicker exit at $station.';
  }

  @override
  String stationsBoardingTipPlatformSigns(String station) {
    return 'Follow platform signs toward $station-bound service.';
  }

  @override
  String stationsSegmentTransfer(
      String from, String to, String base, String forecast) {
    return 'Transfer from $from to $to ($base base, ~$forecast forecast)';
  }

  @override
  String stationsSegmentRide(
      String route, String from, String to, String base, String forecast) {
    return 'Take $route from $from to $to ($base base, ~$forecast forecast)';
  }

  @override
  String stationsFareTotal(String amount) {
    return 'Fare RM $amount';
  }

  @override
  String stationsFareTicketCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tickets',
      one: '1 ticket',
    );
    return '$_temp0';
  }

  @override
  String stationsSegmentFare(String amount) {
    return 'RM $amount';
  }

  @override
  String get arrivalsNextTrain => 'NEXT TRAIN';

  @override
  String get arrivalsSignalLost => 'SIGNAL LOST — TAP TO RETRY';

  @override
  String get arrivalsNoScheduledTrains => 'NO SCHEDULED TRAINS';

  @override
  String get arrivalsOfflineStaticSchedule => 'OFFLINE — STATIC SCHEDULE';

  @override
  String get arrivalsGtfsStaticSchedule => 'GTFS STATIC SCHEDULE';

  @override
  String arrivalsToDestination(String destination) {
    return 'TO $destination';
  }

  @override
  String get arrivalsArriving => 'ARRIVING';

  @override
  String arrivalsMinutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String get crowdBoardTitle => 'Crowd Pulse';

  @override
  String get crowdBoardSearchHint => 'Search station name';

  @override
  String get crowdBoardLoading => 'Loading…';

  @override
  String get crowdBoardEmpty => 'No station crowd data available yet.';

  @override
  String get crowdBoardFilterAll => 'All';

  @override
  String crowdBoardLevelClosed(String label) {
    return '$label · Closed';
  }

  @override
  String get forecastTitle => 'Crowd Outlook';

  @override
  String get forecastNoStations => 'No stations found.';

  @override
  String get forecastStationLabel => 'Station';

  @override
  String forecastLoadFailed(String error) {
    return 'Failed to load crowd forecast: $error';
  }

  @override
  String get forecastEmpty => 'No forecast yet for this station.';

  @override
  String get forecastClosingHoursBody =>
      'Train service is currently closed. Forecasts resume from 6:00 AM.';

  @override
  String get forecastLevel1Subtitle =>
      'Almost empty with seats widely available';

  @override
  String get forecastLevel2Subtitle => 'Comfortable ride with space to spare';

  @override
  String get forecastLevel3Subtitle =>
      'Moderate traffic with routine standing demand';

  @override
  String get forecastLevel4Subtitle =>
      'Heavy crowding with slower boarding likely';

  @override
  String get forecastLevel5Subtitle =>
      'Crowded conditions across the platform and carriage';

  @override
  String get forecastUnknownLevelSubtitle => 'No valid occupancy level';

  @override
  String get forecastExplanationClosed =>
      'Train service is outside operating hours. Stations are shown as unavailable until 6:00 AM.';

  @override
  String get forecastExplanationRecentReports =>
      'based on recent rider reports';

  @override
  String get forecastExplanationHourlyForecast =>
      'based on hourly ridership forecasts';

  @override
  String get forecastExplanationSimulation =>
      'using 10-minute simulation fallback';

  @override
  String get forecastExplanationOfflineFallback =>
      'using offline fallback estimate';

  @override
  String get forecastReasonVeryLowOccupancy => 'very low expected occupancy';

  @override
  String get forecastReasonComfortableSpace =>
      'comfortable space still available';

  @override
  String get forecastReasonModerateStanding =>
      'moderate standing demand likely';

  @override
  String forecastLevelLabel(int level) {
    return 'Level $level';
  }

  @override
  String forecastLevelClosed(int level) {
    return 'Level $level · Closed';
  }

  @override
  String forecastUpdated(String time) {
    return 'Updated: $time';
  }
}
