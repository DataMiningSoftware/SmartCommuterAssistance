import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ms.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ms'),
    Locale('ta'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Smart Commuter Assistant+'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// No description provided for @navTrack.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get navTrack;

  /// No description provided for @navRace.
  ///
  /// In en, this message translates to:
  /// **'Race'**
  String get navRace;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @closingIn.
  ///
  /// In en, this message translates to:
  /// **'Trains closing in {time}'**
  String closingIn(String time);

  /// No description provided for @dataLive.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get dataLive;

  /// No description provided for @dataOffline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get dataOffline;

  /// No description provided for @crowdLevelEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get crowdLevelEmpty;

  /// No description provided for @crowdLevelLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get crowdLevelLight;

  /// No description provided for @crowdLevelModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get crowdLevelModerate;

  /// No description provided for @crowdLevelHeavy.
  ///
  /// In en, this message translates to:
  /// **'Heavy'**
  String get crowdLevelHeavy;

  /// No description provided for @crowdLevelCrowded.
  ///
  /// In en, this message translates to:
  /// **'Crowded'**
  String get crowdLevelCrowded;

  /// No description provided for @crowdLevelUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get crowdLevelUnknown;

  /// No description provided for @mapSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Geographic and schematic views'**
  String get mapSubtitle;

  /// No description provided for @mapGeographic.
  ///
  /// In en, this message translates to:
  /// **'Geographic'**
  String get mapGeographic;

  /// No description provided for @mapTransitMap.
  ///
  /// In en, this message translates to:
  /// **'Transit map'**
  String get mapTransitMap;

  /// No description provided for @mapStationHint.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get mapStationHint;

  /// No description provided for @mapLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load map data: {error}'**
  String mapLoadFailed(String error);

  /// No description provided for @mapTapAnotherStation.
  ///
  /// In en, this message translates to:
  /// **'Tap another station to plan a route from here.'**
  String get mapTapAnotherStation;

  /// No description provided for @mapFindingRoute.
  ///
  /// In en, this message translates to:
  /// **'Finding the best route...'**
  String get mapFindingRoute;

  /// No description provided for @mapRouteSummary.
  ///
  /// In en, this message translates to:
  /// **'{duration} · {transfers} · {crowd} crowd'**
  String mapRouteSummary(String duration, String transfers, String crowd);

  /// No description provided for @mapChooseDifferent.
  ///
  /// In en, this message translates to:
  /// **'Choose different'**
  String get mapChooseDifferent;

  /// No description provided for @mapStartJourney.
  ///
  /// In en, this message translates to:
  /// **'Start journey'**
  String get mapStartJourney;

  /// No description provided for @mapJourneyStarted.
  ///
  /// In en, this message translates to:
  /// **'Journey started — tracking on the Track tab.'**
  String get mapJourneyStarted;

  /// No description provided for @mapSchematicA11yLabel.
  ///
  /// In en, this message translates to:
  /// **'Transit map. Tap a station to select it.'**
  String get mapSchematicA11yLabel;

  /// No description provided for @mapZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get mapZoomIn;

  /// No description provided for @mapZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get mapZoomOut;

  /// No description provided for @dataSourceScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get dataSourceScheduled;

  /// No description provided for @dataSourceRiderReport.
  ///
  /// In en, this message translates to:
  /// **'Rider report'**
  String get dataSourceRiderReport;

  /// No description provided for @dataSourceBlended.
  ///
  /// In en, this message translates to:
  /// **'Blended'**
  String get dataSourceBlended;

  /// No description provided for @dataSourceEstimated.
  ///
  /// In en, this message translates to:
  /// **'Estimated'**
  String get dataSourceEstimated;

  /// No description provided for @dataSourceClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get dataSourceClosed;

  /// No description provided for @dataSourceFallback.
  ///
  /// In en, this message translates to:
  /// **'Fallback'**
  String get dataSourceFallback;

  /// No description provided for @dataSourceUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get dataSourceUnknown;

  /// No description provided for @connectivityConnected.
  ///
  /// In en, this message translates to:
  /// **'You are connected'**
  String get connectivityConnected;

  /// No description provided for @connectivityDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get connectivityDisconnected;

  /// No description provided for @offlineTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get offlineTitle;

  /// No description provided for @offlineBody.
  ///
  /// In en, this message translates to:
  /// **'Some features need a connection. Cached stations, saved routes and local crowd estimates still work.'**
  String get offlineBody;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @continueOffline.
  ///
  /// In en, this message translates to:
  /// **'Continue offline'**
  String get continueOffline;

  /// No description provided for @configurationRequired.
  ///
  /// In en, this message translates to:
  /// **'Configuration Required'**
  String get configurationRequired;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @preparingData.
  ///
  /// In en, this message translates to:
  /// **'Preparing your commute data...'**
  String get preparingData;

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'Startup failed.\n\n{error}'**
  String startupFailed(String error);

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @languageSystemOption.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystemOption;

  /// No description provided for @languageEnglishOption.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglishOption;

  /// No description provided for @languageMalayOption.
  ///
  /// In en, this message translates to:
  /// **'Bahasa Melayu'**
  String get languageMalayOption;

  /// No description provided for @profileCommuter.
  ///
  /// In en, this message translates to:
  /// **'Commuter'**
  String get profileCommuter;

  /// No description provided for @profileUserFallback.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get profileUserFallback;

  /// No description provided for @profileNoAccount.
  ///
  /// In en, this message translates to:
  /// **'No account needed — reports are anonymous'**
  String get profileNoAccount;

  /// No description provided for @profileEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get profileEditTooltip;

  /// No description provided for @preferencesTitle.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferencesTitle;

  /// No description provided for @pushNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get pushNotificationsTitle;

  /// No description provided for @pushNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Delay and route alerts'**
  String get pushNotificationsSubtitle;

  /// No description provided for @offlineModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline Mode'**
  String get offlineModeTitle;

  /// No description provided for @offlineModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cache schedules for weak coverage'**
  String get offlineModeSubtitle;

  /// No description provided for @locationSharingTitle.
  ///
  /// In en, this message translates to:
  /// **'Location Sharing'**
  String get locationSharingTitle;

  /// No description provided for @locationSharingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used for nearby stations; sent rounded to ~1 km'**
  String get locationSharingSubtitle;

  /// No description provided for @mlConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Improve predictions with my trip data'**
  String get mlConsentTitle;

  /// No description provided for @mlConsentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optional. Uses your reports and trip times for model training'**
  String get mlConsentSubtitle;

  /// No description provided for @accessibilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibilityTitle;

  /// No description provided for @accessibilitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Larger labels and stronger contrast'**
  String get accessibilitySubtitle;

  /// No description provided for @darkModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkModeTitle;

  /// No description provided for @darkModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable dark theme for the app'**
  String get darkModeSubtitle;

  /// No description provided for @dataAttributionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Attributions'**
  String get dataAttributionsTitle;

  /// No description provided for @mapTilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Map tiles'**
  String get mapTilesTitle;

  /// No description provided for @mapTilesSource.
  ///
  /// In en, this message translates to:
  /// **'© CartoDB'**
  String get mapTilesSource;

  /// No description provided for @weatherTitle.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get weatherTitle;

  /// No description provided for @weatherSource.
  ///
  /// In en, this message translates to:
  /// **'Weather data by Open-Meteo.com'**
  String get weatherSource;

  /// No description provided for @transitScheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Transit schedule'**
  String get transitScheduleTitle;

  /// No description provided for @transitScheduleSource.
  ///
  /// In en, this message translates to:
  /// **'© Prasarana Malaysia via data.gov.my'**
  String get transitScheduleSource;

  /// No description provided for @quickActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActionsTitle;

  /// No description provided for @routeBuilderTitle.
  ///
  /// In en, this message translates to:
  /// **'Route Builder'**
  String get routeBuilderTitle;

  /// No description provided for @friendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get friendsTitle;

  /// No description provided for @learnTheRailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Learn the Rails'**
  String get learnTheRailsTitle;

  /// No description provided for @favoriteRoutesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorite Routes'**
  String get favoriteRoutesTitle;

  /// No description provided for @travelHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Travel History'**
  String get travelHistoryTitle;

  /// No description provided for @testNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Test notification'**
  String get testNotificationTitle;

  /// No description provided for @testNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'This is a test notification. 🚆'**
  String get testNotificationBody;

  /// No description provided for @helpSupportTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupportTitle;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @privacyPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyTitle;

  /// No description provided for @logoutButton.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutButton;

  /// No description provided for @deleteMyDataButton.
  ///
  /// In en, this message translates to:
  /// **'Delete my data'**
  String get deleteMyDataButton;

  /// No description provided for @deleteAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccountButton;

  /// No description provided for @profileDeleteDataDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete my data?'**
  String get profileDeleteDataDialogTitle;

  /// No description provided for @profileDeleteAccountDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get profileDeleteAccountDialogTitle;

  /// No description provided for @profileDeleteDataDialogBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes your anonymous device profile, account and trip feedback. Your contributed reports are unlinked and anonymised. This cannot be undone.'**
  String get profileDeleteDataDialogBody;

  /// No description provided for @profileDeleteAccountDialogBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account, profile, and travel history. Your contributed reports are unlinked and anonymised. This cannot be undone.'**
  String get profileDeleteAccountDialogBody;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @deleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteButton;

  /// No description provided for @accountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Account deleted.'**
  String get accountDeleted;

  /// No description provided for @deleteAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete account automatically. Please use the account deletion link in the privacy policy.'**
  String get deleteAccountFailed;

  /// No description provided for @editProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfileTitle;

  /// No description provided for @handleLabel.
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get handleLabel;

  /// No description provided for @displayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayNameLabel;

  /// No description provided for @bioLabel.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get bioLabel;

  /// No description provided for @avatarColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Avatar color (hex, optional)'**
  String get avatarColorLabel;

  /// No description provided for @homeStationLabel.
  ///
  /// In en, this message translates to:
  /// **'Home station ID (optional)'**
  String get homeStationLabel;

  /// No description provided for @favoriteLineLabel.
  ///
  /// In en, this message translates to:
  /// **'Favorite line (optional)'**
  String get favoriteLineLabel;

  /// No description provided for @allowFindByHandle.
  ///
  /// In en, this message translates to:
  /// **'Allow others to find me by handle'**
  String get allowFindByHandle;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @aboutDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'About Smart Commuter Assistant+'**
  String get aboutDialogTitle;

  /// No description provided for @aboutDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Smart Commuter Assistant+ v{version}\n\nDynamic Navigation & Occupancy Computations.\n\nAn intelligent companion for Malaysian public transport.\n\nAn independent, unofficial app — not affiliated with Rapid KL, Prasarana Malaysia, or KTMB.'**
  String aboutDialogBody(String version);

  /// No description provided for @okButton.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okButton;

  /// No description provided for @railIndependenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Rail Independence'**
  String get railIndependenceTitle;

  /// No description provided for @railIndependenceBody.
  ///
  /// In en, this message translates to:
  /// **'You know {stations} {stations, plural, =1{station} other{stations}} and answer {accuracy}% of trivia correctly. Keep going — the goal is to not need us.'**
  String railIndependenceBody(int stations, int accuracy);

  /// No description provided for @locationServicesOff.
  ///
  /// In en, this message translates to:
  /// **'Turn on Location Services to use nearby stations.'**
  String get locationServicesOff;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied in system settings.'**
  String get locationPermissionDenied;

  /// No description provided for @loginWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get loginWelcome;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Login to view forecasts, routes, and your travel history.'**
  String get loginSubtitle;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordLabel;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get emailInvalid;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Use at least 6 characters'**
  String get passwordMinLength;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

  /// No description provided for @fullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullNameLabel;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginButton;

  /// No description provided for @signInWithGoogleButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogleButton;

  /// No description provided for @guestModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Guest mode enabled. You can continue without an account.'**
  String get guestModeEnabled;

  /// No description provided for @guestModeFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to enter guest mode right now. Please try again.'**
  String get guestModeFailed;

  /// No description provided for @continueAsGuestButton.
  ///
  /// In en, this message translates to:
  /// **'Continue as guest'**
  String get continueAsGuestButton;

  /// No description provided for @createAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccountButton;

  /// No description provided for @signInWithPhoneButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in with phone'**
  String get signInWithPhoneButton;

  /// No description provided for @signUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Your Pass'**
  String get signUpTitle;

  /// No description provided for @creatingAccount.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get creatingAccount;

  /// No description provided for @accountCreatedVerify.
  ///
  /// In en, this message translates to:
  /// **'Account created! Check your email to verify it, then log in.'**
  String get accountCreatedVerify;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumberLabel;

  /// No description provided for @phoneNumberHint.
  ///
  /// In en, this message translates to:
  /// **'+60 12-345 6789'**
  String get phoneNumberHint;

  /// No description provided for @verificationCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get verificationCodeLabel;

  /// No description provided for @pleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Please wait…'**
  String get pleaseWait;

  /// No description provided for @verifyCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Verify code'**
  String get verifyCodeButton;

  /// No description provided for @sendCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCodeButton;

  /// No description provided for @otpInfo.
  ///
  /// In en, this message translates to:
  /// **'A one-time code will be sent by SMS. Requires the Phone provider to be enabled in Supabase.'**
  String get otpInfo;

  /// No description provided for @supportContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Email the developer'**
  String get supportContactTitle;

  /// No description provided for @supportContactBody.
  ///
  /// In en, this message translates to:
  /// **'Questions, bug reports, or feature ideas? We usually reply within a few days.'**
  String get supportContactBody;

  /// No description provided for @supportSendEmailButton.
  ///
  /// In en, this message translates to:
  /// **'Send email'**
  String get supportSendEmailButton;

  /// No description provided for @supportCopyEmailButton.
  ///
  /// In en, this message translates to:
  /// **'Copy email address'**
  String get supportCopyEmailButton;

  /// No description provided for @supportEmailCopied.
  ///
  /// In en, this message translates to:
  /// **'Email address copied'**
  String get supportEmailCopied;

  /// No description provided for @supportNoMailApp.
  ///
  /// In en, this message translates to:
  /// **'No email app found — address copied instead'**
  String get supportNoMailApp;

  /// No description provided for @supportFaqTitle.
  ///
  /// In en, this message translates to:
  /// **'Frequently asked questions'**
  String get supportFaqTitle;

  /// No description provided for @supportFaqOfflineQuestion.
  ///
  /// In en, this message translates to:
  /// **'Why do some features stop working offline?'**
  String get supportFaqOfflineQuestion;

  /// No description provided for @supportFaqOfflineAnswer.
  ///
  /// In en, this message translates to:
  /// **'Live arrivals, crowd forecasts and route planning need a connection. Stations, saved routes and the last cached forecasts keep working in offline mode.'**
  String get supportFaqOfflineAnswer;

  /// No description provided for @supportFaqCrowdQuestion.
  ///
  /// In en, this message translates to:
  /// **'Where do crowd forecasts come from?'**
  String get supportFaqCrowdQuestion;

  /// No description provided for @supportFaqCrowdAnswer.
  ///
  /// In en, this message translates to:
  /// **'Hourly forecasts are trained on rider reports and blended with recent community reports. Verified reports from different riders carry more weight.'**
  String get supportFaqCrowdAnswer;

  /// No description provided for @supportFaqDelayQuestion.
  ///
  /// In en, this message translates to:
  /// **'How do delay reports work?'**
  String get supportFaqDelayQuestion;

  /// No description provided for @supportFaqDelayAnswer.
  ///
  /// In en, this message translates to:
  /// **'When at least 3 riders report a delay on the same line and direction within 20 minutes, other riders see a delay signal and their ETA is adjusted automatically.'**
  String get supportFaqDelayAnswer;

  /// No description provided for @supportFaqPrivacyQuestion.
  ///
  /// In en, this message translates to:
  /// **'What happens to my data?'**
  String get supportFaqPrivacyQuestion;

  /// No description provided for @supportFaqPrivacyAnswer.
  ///
  /// In en, this message translates to:
  /// **'The app works anonymously without an account. Location stays on your device except rounded (~1 km) crowd reports you choose to send. You can delete everything from Profile.'**
  String get supportFaqPrivacyAnswer;

  /// No description provided for @supportFaqEtaQuestion.
  ///
  /// In en, this message translates to:
  /// **'How accurate are the ETAs?'**
  String get supportFaqEtaQuestion;

  /// No description provided for @supportFaqEtaAnswer.
  ///
  /// In en, this message translates to:
  /// **'ETAs are pinned when you reach your origin station and count down steadily. They adjust for delay and crowd reports, and improve over time as trip feedback is collected.'**
  String get supportFaqEtaAnswer;

  /// No description provided for @supportLinksTitle.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get supportLinksTitle;

  /// No description provided for @supportDeleteDataLink.
  ///
  /// In en, this message translates to:
  /// **'Delete your data (web)'**
  String get supportDeleteDataLink;

  /// No description provided for @supportIssuesLink.
  ///
  /// In en, this message translates to:
  /// **'Report an issue on GitHub'**
  String get supportIssuesLink;

  /// No description provided for @supportEmailSubject.
  ///
  /// In en, this message translates to:
  /// **'[Smart Commuter Assistant+] Support — v{version}'**
  String supportEmailSubject(String version);

  /// No description provided for @supportEmailBody.
  ///
  /// In en, this message translates to:
  /// **'Describe your issue here.\n\n---\nApp: Smart Commuter Assistant+ {version} ({build})\nPlatform: {platform}\nLocale: {locale}\nConnection: {connection}\n---'**
  String supportEmailBody(String version, String build, String platform,
      String locale, String connection);

  /// No description provided for @homeStationUnavailableClosingHours.
  ///
  /// In en, this message translates to:
  /// **'{station} is unavailable during closing hours for the selected departure time.'**
  String homeStationUnavailableClosingHours(String station);

  /// No description provided for @homeLocationRequired.
  ///
  /// In en, this message translates to:
  /// **'Location is required before starting a trip.'**
  String get homeLocationRequired;

  /// No description provided for @homeNearestStationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not determine your nearest station yet.'**
  String get homeNearestStationUnavailable;

  /// No description provided for @homeNoRouteFound.
  ///
  /// In en, this message translates to:
  /// **'No route found for {station}.'**
  String homeNoRouteFound(String station);

  /// No description provided for @homePrepareTripFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare trip: {error}'**
  String homePrepareTripFailed(String error);

  /// No description provided for @homeRouteCrowdedTitle.
  ///
  /// In en, this message translates to:
  /// **'Looks like your route is crowded.'**
  String get homeRouteCrowdedTitle;

  /// No description provided for @homeCalmerTripAvailable.
  ///
  /// In en, this message translates to:
  /// **'A calmer trip to {destination} is available, but it may take longer.'**
  String homeCalmerTripAvailable(String destination);

  /// No description provided for @homeEfficientRoute.
  ///
  /// In en, this message translates to:
  /// **'Efficient route'**
  String get homeEfficientRoute;

  /// No description provided for @homeFastestOptionNow.
  ///
  /// In en, this message translates to:
  /// **'Fastest option right now'**
  String get homeFastestOptionNow;

  /// No description provided for @homeKeepThisRoute.
  ///
  /// In en, this message translates to:
  /// **'Keep this route'**
  String get homeKeepThisRoute;

  /// No description provided for @homeRelaxedRoute.
  ///
  /// In en, this message translates to:
  /// **'Relaxed route'**
  String get homeRelaxedRoute;

  /// No description provided for @homeCalmerRideDetour.
  ///
  /// In en, this message translates to:
  /// **'Calmer ride with a small detour'**
  String get homeCalmerRideDetour;

  /// No description provided for @homeTakeRelaxedRoute.
  ///
  /// In en, this message translates to:
  /// **'Take a more relaxed route'**
  String get homeTakeRelaxedRoute;

  /// No description provided for @homeLocationPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Location Privacy'**
  String get homeLocationPrivacyTitle;

  /// No description provided for @homeLocationPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Your location is used to find nearby stations and provide arrival estimates. Coordinates are rounded to ~1 km precision before being sent to our servers. Your exact location is never stored or shared.\n\nYou can change this later in Profile settings.'**
  String get homeLocationPrivacyBody;

  /// No description provided for @homeSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get homeSkip;

  /// No description provided for @homeAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get homeAllow;

  /// No description provided for @homeCrowdLevelsLower.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 crowd level lower} other{{count} crowd levels lower}}'**
  String homeCrowdLevelsLower(int count);

  /// No description provided for @homeCrowdLevelsHigher.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 crowd level higher} other{{count} crowd levels higher}}'**
  String homeCrowdLevelsHigher(int count);

  /// No description provided for @homeFastest.
  ///
  /// In en, this message translates to:
  /// **'Fastest'**
  String get homeFastest;

  /// No description provided for @homeNoTimePenalty.
  ///
  /// In en, this message translates to:
  /// **'No time penalty'**
  String get homeNoTimePenalty;

  /// No description provided for @homePlusMinutes.
  ///
  /// In en, this message translates to:
  /// **'+{minutes} min'**
  String homePlusMinutes(int minutes);

  /// No description provided for @homeDirectRide.
  ///
  /// In en, this message translates to:
  /// **'Direct ride'**
  String get homeDirectRide;

  /// No description provided for @homeTransferCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transfer} other{{count} transfers}}'**
  String homeTransferCount(int count);

  /// No description provided for @homeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Home base'**
  String get homeSubtitle;

  /// No description provided for @homeHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Ride smart, skip the squeeze.'**
  String get homeHeroTitle;

  /// No description provided for @homeHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live crowd-aware routing, trip tracking, and route glow in one place.'**
  String get homeHeroSubtitle;

  /// No description provided for @homeAllStations.
  ///
  /// In en, this message translates to:
  /// **'All Stations'**
  String get homeAllStations;

  /// No description provided for @homeAllStationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse lines and interchanges'**
  String get homeAllStationsSubtitle;

  /// No description provided for @homeTrackRoute.
  ///
  /// In en, this message translates to:
  /// **'Track Route'**
  String get homeTrackRoute;

  /// No description provided for @homeResumeTrip.
  ///
  /// In en, this message translates to:
  /// **'Resume Trip'**
  String get homeResumeTrip;

  /// No description provided for @homeStartTripHint.
  ///
  /// In en, this message translates to:
  /// **'Start a trip to unlock tracking'**
  String get homeStartTripHint;

  /// No description provided for @homeTripDirection.
  ///
  /// In en, this message translates to:
  /// **'{origin} to {destination}'**
  String homeTripDirection(String origin, String destination);

  /// No description provided for @homeRouteModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get homeRouteModeAuto;

  /// No description provided for @homeRouteModeEfficient.
  ///
  /// In en, this message translates to:
  /// **'Efficient'**
  String get homeRouteModeEfficient;

  /// No description provided for @homeRouteModeRelaxed.
  ///
  /// In en, this message translates to:
  /// **'Relaxed'**
  String get homeRouteModeRelaxed;

  /// No description provided for @homeRouteModeAutoHelper.
  ///
  /// In en, this message translates to:
  /// **'Compare efficient and relaxed routes, then ask only when the calmer route is worth it.'**
  String get homeRouteModeAutoHelper;

  /// No description provided for @homeRouteModeEfficientHelper.
  ///
  /// In en, this message translates to:
  /// **'Always keep the fastest route.'**
  String get homeRouteModeEfficientHelper;

  /// No description provided for @homeRouteModeComfortHelper.
  ///
  /// In en, this message translates to:
  /// **'Prefer lower crowd even if the trip takes a little longer.'**
  String get homeRouteModeComfortHelper;

  /// No description provided for @homePickNextStop.
  ///
  /// In en, this message translates to:
  /// **'Pick Your Next Stop'**
  String get homePickNextStop;

  /// No description provided for @homeSearchDestinationHint.
  ///
  /// In en, this message translates to:
  /// **'Search a destination, set your routing style, and preview crowd before you leave.'**
  String get homeSearchDestinationHint;

  /// No description provided for @homeRouteStyle.
  ///
  /// In en, this message translates to:
  /// **'Route style'**
  String get homeRouteStyle;

  /// No description provided for @homeLoadingStations.
  ///
  /// In en, this message translates to:
  /// **'Loading stations…'**
  String get homeLoadingStations;

  /// No description provided for @homeLoadStationsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load stations: {error}'**
  String homeLoadStationsFailed(String error);

  /// No description provided for @homeNoStationNames.
  ///
  /// In en, this message translates to:
  /// **'No station names available yet. Showing a local sample list instead.'**
  String get homeNoStationNames;

  /// No description provided for @homeSearchTrainStation.
  ///
  /// In en, this message translates to:
  /// **'Search train station'**
  String get homeSearchTrainStation;

  /// No description provided for @homeClosingHours.
  ///
  /// In en, this message translates to:
  /// **'Closing hours'**
  String get homeClosingHours;

  /// No description provided for @homePlanAhead.
  ///
  /// In en, this message translates to:
  /// **'Plan Ahead'**
  String get homePlanAhead;

  /// No description provided for @homeLiveMapUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Live map unavailable'**
  String get homeLiveMapUnavailable;

  /// No description provided for @homeEtaSyncing.
  ///
  /// In en, this message translates to:
  /// **'ETA syncing'**
  String get homeEtaSyncing;

  /// No description provided for @homeArrivingNow.
  ///
  /// In en, this message translates to:
  /// **'Arriving now'**
  String get homeArrivingNow;

  /// No description provided for @homeArriveBy.
  ///
  /// In en, this message translates to:
  /// **'Arrive by {time}'**
  String homeArriveBy(String time);

  /// No description provided for @homeLiveTrip.
  ///
  /// In en, this message translates to:
  /// **'Live Trip'**
  String get homeLiveTrip;

  /// No description provided for @homeViewMap.
  ///
  /// In en, this message translates to:
  /// **'View map'**
  String get homeViewMap;

  /// No description provided for @homeRelaxedRoutingActive.
  ///
  /// In en, this message translates to:
  /// **'Relaxed routing is active.'**
  String get homeRelaxedRoutingActive;

  /// No description provided for @homeLiveTrackingReady.
  ///
  /// In en, this message translates to:
  /// **'Live tracking is ready.'**
  String get homeLiveTrackingReady;

  /// No description provided for @homeYouAreHere.
  ///
  /// In en, this message translates to:
  /// **'You are here'**
  String get homeYouAreHere;

  /// No description provided for @homeMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get homeMinutesShort;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Where to today?'**
  String get homeGreeting;

  /// No description provided for @homeFastRouteTitle.
  ///
  /// In en, this message translates to:
  /// **'⚡ Fast route'**
  String get homeFastRouteTitle;

  /// No description provided for @homeLessCrowdedTitle.
  ///
  /// In en, this message translates to:
  /// **'🌿 Less crowded'**
  String get homeLessCrowdedTitle;

  /// No description provided for @homeKeepFastRoute.
  ///
  /// In en, this message translates to:
  /// **'Keep with fast route'**
  String get homeKeepFastRoute;

  /// No description provided for @homeTakeLessCrowdedRoute.
  ///
  /// In en, this message translates to:
  /// **'Take a less crowded route'**
  String get homeTakeLessCrowdedRoute;

  /// No description provided for @languageChineseOption.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get languageChineseOption;

  /// No description provided for @languageTamilOption.
  ///
  /// In en, this message translates to:
  /// **'தமிழ்'**
  String get languageTamilOption;

  /// No description provided for @homeTripEtaTo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min to {destination}'**
  String homeTripEtaTo(int minutes, String destination);

  /// No description provided for @homeCrowdLevelPrefix.
  ///
  /// In en, this message translates to:
  /// **'Crowd level: '**
  String get homeCrowdLevelPrefix;

  /// No description provided for @homeOpenTracking.
  ///
  /// In en, this message translates to:
  /// **'Open tracking'**
  String get homeOpenTracking;

  /// No description provided for @homeStationCrowdBoard.
  ///
  /// In en, this message translates to:
  /// **'Station Crowd Board'**
  String get homeStationCrowdBoard;

  /// No description provided for @homeNearestStationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Showing the nearest station to your current location.'**
  String get homeNearestStationSubtitle;

  /// No description provided for @homeViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get homeViewAll;

  /// No description provided for @homeRefreshNearbyStations.
  ///
  /// In en, this message translates to:
  /// **'Refresh nearby stations'**
  String get homeRefreshNearbyStations;

  /// No description provided for @homeLoadCrowdBoardFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load crowd board: {error}'**
  String homeLoadCrowdBoardFailed(String error);

  /// No description provided for @homeLocationSyncing.
  ///
  /// In en, this message translates to:
  /// **'Location is still syncing. Pull to refresh or try again in a moment.'**
  String get homeLocationSyncing;

  /// No description provided for @homeMetersAway.
  ///
  /// In en, this message translates to:
  /// **'{distance} m away'**
  String homeMetersAway(String distance);

  /// No description provided for @homeReportCrowded.
  ///
  /// In en, this message translates to:
  /// **'Report crowded'**
  String get homeReportCrowded;

  /// No description provided for @homeEtaLabel.
  ///
  /// In en, this message translates to:
  /// **'ETA {duration}'**
  String homeEtaLabel(String duration);

  /// No description provided for @homeDurationMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String homeDurationMinutesShort(int minutes);

  /// No description provided for @homeDurationHoursShort.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String homeDurationHoursShort(int hours);

  /// No description provided for @homeDurationHoursMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String homeDurationHoursMinutesShort(int hours, int minutes);

  /// No description provided for @homeRoutePending.
  ///
  /// In en, this message translates to:
  /// **'Route pending'**
  String get homeRoutePending;

  /// No description provided for @trackKeepCrowdedRoute.
  ///
  /// In en, this message translates to:
  /// **'Keep with crowded route'**
  String get trackKeepCrowdedRoute;

  /// No description provided for @trackPlanYourTrip.
  ///
  /// In en, this message translates to:
  /// **'Plan Your Trip'**
  String get trackPlanYourTrip;

  /// No description provided for @trackSelectOriginDestination.
  ///
  /// In en, this message translates to:
  /// **'Select origin and destination stations.'**
  String get trackSelectOriginDestination;

  /// No description provided for @trackFromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get trackFromLabel;

  /// No description provided for @trackToLabel.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get trackToLabel;

  /// No description provided for @trackSetArrivalTime.
  ///
  /// In en, this message translates to:
  /// **'Set arrival time'**
  String get trackSetArrivalTime;

  /// No description provided for @trackWhenArrive.
  ///
  /// In en, this message translates to:
  /// **'When do you want to arrive?'**
  String get trackWhenArrive;

  /// No description provided for @trackTargetArrivalHint.
  ///
  /// In en, this message translates to:
  /// **'Set your target arrival time and we\'ll calculate when to leave.'**
  String get trackTargetArrivalHint;

  /// No description provided for @trackCalculate.
  ///
  /// In en, this message translates to:
  /// **'Calculate'**
  String get trackCalculate;

  /// No description provided for @trackCalculatingSchedule.
  ///
  /// In en, this message translates to:
  /// **'Calculating schedule...'**
  String get trackCalculatingSchedule;

  /// No description provided for @trackNoRouteFoundTo.
  ///
  /// In en, this message translates to:
  /// **'No route found to {station}.'**
  String trackNoRouteFoundTo(String station);

  /// No description provided for @trackPlanAheadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not plan ahead: {error}'**
  String trackPlanAheadFailed(String error);

  /// No description provided for @trackTripPlan.
  ///
  /// In en, this message translates to:
  /// **'Trip Plan'**
  String get trackTripPlan;

  /// No description provided for @trackLeaveBy.
  ///
  /// In en, this message translates to:
  /// **'Leave by'**
  String get trackLeaveBy;

  /// No description provided for @trackWalkTo.
  ///
  /// In en, this message translates to:
  /// **'Walk to {station}'**
  String trackWalkTo(String station);

  /// No description provided for @trackDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String trackDurationMinutes(int minutes);

  /// No description provided for @trackVia.
  ///
  /// In en, this message translates to:
  /// **'Via {routes}'**
  String trackVia(String routes);

  /// No description provided for @trackArriveAt.
  ///
  /// In en, this message translates to:
  /// **'Arrive at {station}'**
  String trackArriveAt(String station);

  /// No description provided for @trackEstimatedTotal.
  ///
  /// In en, this message translates to:
  /// **'Estimated total: {minutes} min'**
  String trackEstimatedTotal(int minutes);

  /// No description provided for @trackStartThisTripNow.
  ///
  /// In en, this message translates to:
  /// **'Start this trip now'**
  String get trackStartThisTripNow;

  /// No description provided for @trackStationUnavailableClosingHours.
  ///
  /// In en, this message translates to:
  /// **'{station} is unavailable during closing hours.'**
  String trackStationUnavailableClosingHours(String station);

  /// No description provided for @trackEnableLocationServices.
  ///
  /// In en, this message translates to:
  /// **'Enable location services before starting a trip.'**
  String get trackEnableLocationServices;

  /// No description provided for @trackLocationPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required to start a trip.'**
  String get trackLocationPermissionRequired;

  /// No description provided for @trackChooseDestinationBeyond.
  ///
  /// In en, this message translates to:
  /// **'Choose a destination beyond {station}.'**
  String trackChooseDestinationBeyond(String station);

  /// No description provided for @trackStartTripFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start trip: {error}'**
  String trackStartTripFailed(String error);

  /// No description provided for @trackSwitchDestinationFrom.
  ///
  /// In en, this message translates to:
  /// **'Switch destination from {station}'**
  String trackSwitchDestinationFrom(String station);

  /// No description provided for @trackSwitchDestinationHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a new target station and the route will restart from where you are now.'**
  String get trackSwitchDestinationHint;

  /// No description provided for @trackSearchStationOrCode.
  ///
  /// In en, this message translates to:
  /// **'Search station or code'**
  String get trackSearchStationOrCode;

  /// No description provided for @trackAreYouOkay.
  ///
  /// In en, this message translates to:
  /// **'Are you okay?'**
  String get trackAreYouOkay;

  /// No description provided for @trackInactivityBody.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t moved in a while. Is everything alright?'**
  String get trackInactivityBody;

  /// No description provided for @trackImFine.
  ///
  /// In en, this message translates to:
  /// **'I\'m fine'**
  String get trackImFine;

  /// No description provided for @trackCallEmergencyContact.
  ///
  /// In en, this message translates to:
  /// **'Call emergency contact'**
  String get trackCallEmergencyContact;

  /// No description provided for @trackCancelTrip.
  ///
  /// In en, this message translates to:
  /// **'Cancel trip'**
  String get trackCancelTrip;

  /// No description provided for @trackEmergencyDialer.
  ///
  /// In en, this message translates to:
  /// **'Emergency contact dialer would open here.'**
  String get trackEmergencyDialer;

  /// No description provided for @trackRouteRecalculated.
  ///
  /// In en, this message translates to:
  /// **'Route recalculated'**
  String get trackRouteRecalculated;

  /// No description provided for @trackDeviatedFromRoute.
  ///
  /// In en, this message translates to:
  /// **'You\'ve deviated from your route a few times.'**
  String get trackDeviatedFromRoute;

  /// No description provided for @trackPickNewDestination.
  ///
  /// In en, this message translates to:
  /// **'Would you like to pick a new destination instead?'**
  String get trackPickNewDestination;

  /// No description provided for @trackContinueToDestination.
  ///
  /// In en, this message translates to:
  /// **'Continue to current destination'**
  String get trackContinueToDestination;

  /// No description provided for @trackChooseNewDestination.
  ///
  /// In en, this message translates to:
  /// **'Choose a new destination'**
  String get trackChooseNewDestination;

  /// No description provided for @trackLocatingTrain.
  ///
  /// In en, this message translates to:
  /// **'Locating train'**
  String get trackLocatingTrain;

  /// No description provided for @trackChangeLineAt.
  ///
  /// In en, this message translates to:
  /// **'Change line at {station}'**
  String trackChangeLineAt(String station);

  /// No description provided for @trackSwitchToLine.
  ///
  /// In en, this message translates to:
  /// **'Switch to the {routeId} line after this station.'**
  String trackSwitchToLine(String routeId);

  /// No description provided for @trackReachedDestination.
  ///
  /// In en, this message translates to:
  /// **'You have reached {destination}'**
  String trackReachedDestination(String destination);

  /// No description provided for @trackTripEnded.
  ///
  /// In en, this message translates to:
  /// **'Your trip has ended.'**
  String get trackTripEnded;

  /// No description provided for @trackRidersReportDelays.
  ///
  /// In en, this message translates to:
  /// **'{count} riders report delays on {route} · +{minutes} min'**
  String trackRidersReportDelays(int count, String route, int minutes);

  /// No description provided for @trackDelayReportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not submit the delay report. Please try again.'**
  String get trackDelayReportFailed;

  /// No description provided for @trackCrowdedReported.
  ///
  /// In en, this message translates to:
  /// **'Crowded train reported for {stopId}.'**
  String trackCrowdedReported(String stopId);

  /// No description provided for @trackDelayReported.
  ///
  /// In en, this message translates to:
  /// **'Delay reported for {stopId}.'**
  String trackDelayReported(String stopId);

  /// No description provided for @trackReportSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not submit report: {error}'**
  String trackReportSubmitFailed(String error);

  /// No description provided for @trackCancelActiveTripTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel active trip?'**
  String get trackCancelActiveTripTitle;

  /// No description provided for @trackCancelActiveTripBody.
  ///
  /// In en, this message translates to:
  /// **'This will stop live tracking and clear the saved route.'**
  String get trackCancelActiveTripBody;

  /// No description provided for @trackKeepTrip.
  ///
  /// In en, this message translates to:
  /// **'Keep Trip'**
  String get trackKeepTrip;

  /// No description provided for @trackTitleLeading.
  ///
  /// In en, this message translates to:
  /// **'Trip'**
  String get trackTitleLeading;

  /// No description provided for @trackTitleAccent.
  ///
  /// In en, this message translates to:
  /// **'Motion'**
  String get trackTitleAccent;

  /// No description provided for @trackTitleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tracking'**
  String get trackTitleSubtitle;

  /// No description provided for @trackPickStationFromResults.
  ///
  /// In en, this message translates to:
  /// **'Pick a station from the search results.'**
  String get trackPickStationFromResults;

  /// No description provided for @trackPreparingTimeline.
  ///
  /// In en, this message translates to:
  /// **'Preparing route timeline...'**
  String get trackPreparingTimeline;

  /// No description provided for @trackSending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get trackSending;

  /// No description provided for @trackReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get trackReport;

  /// No description provided for @trackSyncing.
  ///
  /// In en, this message translates to:
  /// **'syncing'**
  String get trackSyncing;

  /// No description provided for @trackArrived.
  ///
  /// In en, this message translates to:
  /// **'Arrived'**
  String get trackArrived;

  /// No description provided for @trackStopsRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stop} other{{count} stops}}'**
  String trackStopsRemaining(int count);

  /// No description provided for @trackTimeLeft.
  ///
  /// In en, this message translates to:
  /// **'Time left'**
  String get trackTimeLeft;

  /// No description provided for @trackArriveBy.
  ///
  /// In en, this message translates to:
  /// **'Arrive by'**
  String get trackArriveBy;

  /// No description provided for @trackPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String trackPercent(int percent);

  /// No description provided for @trackPercentCompleted.
  ///
  /// In en, this message translates to:
  /// **'{percent}% completed'**
  String trackPercentCompleted(int percent);

  /// No description provided for @trackChangeDestination.
  ///
  /// In en, this message translates to:
  /// **'Change destination'**
  String get trackChangeDestination;

  /// No description provided for @trackChangeTo.
  ///
  /// In en, this message translates to:
  /// **'Change to {routeId}'**
  String trackChangeTo(String routeId);

  /// No description provided for @trackStartStation.
  ///
  /// In en, this message translates to:
  /// **'Start station'**
  String get trackStartStation;

  /// No description provided for @trackEndStation.
  ///
  /// In en, this message translates to:
  /// **'End station'**
  String get trackEndStation;

  /// No description provided for @trackForecast.
  ///
  /// In en, this message translates to:
  /// **'Forecast: {label}'**
  String trackForecast(String label);

  /// No description provided for @trackCrowdedTrain.
  ///
  /// In en, this message translates to:
  /// **'Crowded train'**
  String get trackCrowdedTrain;

  /// No description provided for @trackDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay'**
  String get trackDelay;

  /// No description provided for @trackNoActiveTrip.
  ///
  /// In en, this message translates to:
  /// **'No active trip yet.'**
  String get trackNoActiveTrip;

  /// No description provided for @trackNoActiveTripBody.
  ///
  /// In en, this message translates to:
  /// **'Search for a destination here and start tracking straight from the track page.'**
  String get trackNoActiveTripBody;

  /// No description provided for @trackStartingTrip.
  ///
  /// In en, this message translates to:
  /// **'Starting trip...'**
  String get trackStartingTrip;

  /// No description provided for @trackSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get trackSearch;

  /// No description provided for @trackPlanAhead.
  ///
  /// In en, this message translates to:
  /// **'Plan ahead'**
  String get trackPlanAhead;

  /// No description provided for @trackComfortRoute.
  ///
  /// In en, this message translates to:
  /// **'Comfort route'**
  String get trackComfortRoute;

  /// No description provided for @trackEfficiencyRoute.
  ///
  /// In en, this message translates to:
  /// **'Efficiency route'**
  String get trackEfficiencyRoute;

  /// No description provided for @trackCrowdShort.
  ///
  /// In en, this message translates to:
  /// **'Crowd: {label}'**
  String trackCrowdShort(String label);

  /// No description provided for @trackLocatingTrainPath.
  ///
  /// In en, this message translates to:
  /// **'Locating train path'**
  String get trackLocatingTrainPath;

  /// No description provided for @trackRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining: {distance}'**
  String trackRemaining(String distance);

  /// No description provided for @trackCalculatingEta.
  ///
  /// In en, this message translates to:
  /// **'Calculating ETA'**
  String get trackCalculatingEta;

  /// No description provided for @trackJourney.
  ///
  /// In en, this message translates to:
  /// **'Journey: {duration}'**
  String trackJourney(String duration);

  /// No description provided for @trackOriginDestination.
  ///
  /// In en, this message translates to:
  /// **'{origin} -> {destination}'**
  String trackOriginDestination(String origin, String destination);

  /// No description provided for @stationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Station Atlas'**
  String get stationsTitle;

  /// No description provided for @stationsNearestTooltip.
  ///
  /// In en, this message translates to:
  /// **'Nearest'**
  String get stationsNearestTooltip;

  /// No description provided for @stationsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by station, line, or code'**
  String get stationsSearchHint;

  /// No description provided for @stationsClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get stationsClearSearch;

  /// No description provided for @stationsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load stations from Supabase'**
  String get stationsLoadFailed;

  /// No description provided for @stationsEmptyTable.
  ///
  /// In en, this message translates to:
  /// **'Connected, but table train_stops_kl has 0 rows.'**
  String get stationsEmptyTable;

  /// No description provided for @stationsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No stations match your search.'**
  String get stationsNoMatch;

  /// No description provided for @stationsLineColors.
  ///
  /// In en, this message translates to:
  /// **'Line Colors'**
  String get stationsLineColors;

  /// No description provided for @stationsArrivalsButton.
  ///
  /// In en, this message translates to:
  /// **'Arrivals'**
  String get stationsArrivalsButton;

  /// No description provided for @stationsUnnamedStation.
  ///
  /// In en, this message translates to:
  /// **'Unnamed Station'**
  String get stationsUnnamedStation;

  /// No description provided for @stationsUnknownCrowdLevel.
  ///
  /// In en, this message translates to:
  /// **'Unknown crowd level'**
  String get stationsUnknownCrowdLevel;

  /// No description provided for @stationsUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get stationsUnknown;

  /// No description provided for @stationsLocationServicesDisabled.
  ///
  /// In en, this message translates to:
  /// **'Location services are disabled.'**
  String get stationsLocationServicesDisabled;

  /// No description provided for @stationsLocationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied.'**
  String get stationsLocationPermissionDenied;

  /// No description provided for @stationsLocationPermissionDeniedForever.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied forever. Enable it in settings.'**
  String get stationsLocationPermissionDeniedForever;

  /// No description provided for @stationsNoValidCoordinates.
  ///
  /// In en, this message translates to:
  /// **'No valid stop_lat/stop_lon found to calculate distance.'**
  String get stationsNoValidCoordinates;

  /// No description provided for @stationsNearestMessage.
  ///
  /// In en, this message translates to:
  /// **'Nearest: {station} ({distance}) at {lat}, {lon}'**
  String stationsNearestMessage(
      String station, String distance, String lat, String lon);

  /// No description provided for @stationsLocationFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to get location: {error}'**
  String stationsLocationFailed(String error);

  /// No description provided for @stationsMissingStopId.
  ///
  /// In en, this message translates to:
  /// **'Selected station is missing stop_id.'**
  String get stationsMissingStopId;

  /// No description provided for @stationsNearestOriginFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not determine nearest origin station.'**
  String get stationsNearestOriginFailed;

  /// No description provided for @stationsAlreadyAtStation.
  ///
  /// In en, this message translates to:
  /// **'You are already nearest to this station.'**
  String get stationsAlreadyAtStation;

  /// No description provided for @stationsNoRouteFoundFromTo.
  ///
  /// In en, this message translates to:
  /// **'No route found from {origin} to {destination}.'**
  String stationsNoRouteFoundFromTo(String origin, String destination);

  /// No description provided for @stationsNoOfflineRouteCache.
  ///
  /// In en, this message translates to:
  /// **'No offline route cache available. Go online once to sync route_connections.'**
  String get stationsNoOfflineRouteCache;

  /// No description provided for @stationsWalkHiddenFarFromStations.
  ///
  /// In en, this message translates to:
  /// **'Current location is far from supported stations. Walk distance is hidden from ETA.'**
  String get stationsWalkHiddenFarFromStations;

  /// No description provided for @stationsPlanRouteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to plan route: {error}'**
  String stationsPlanRouteFailed(String error);

  /// No description provided for @stationsSelectedTimeInPast.
  ///
  /// In en, this message translates to:
  /// **'Selected time is in the past. Using current time instead.'**
  String get stationsSelectedTimeInPast;

  /// No description provided for @stationsWhenDepartTitle.
  ///
  /// In en, this message translates to:
  /// **'When do you want to depart?'**
  String get stationsWhenDepartTitle;

  /// No description provided for @stationsChooseDepartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose now or pick a specific date and time.'**
  String get stationsChooseDepartSubtitle;

  /// No description provided for @stationsLeaveNowButton.
  ///
  /// In en, this message translates to:
  /// **'Leave Now'**
  String get stationsLeaveNowButton;

  /// No description provided for @stationsChooseDateTimeButton.
  ///
  /// In en, this message translates to:
  /// **'Choose Date & Time'**
  String get stationsChooseDateTimeButton;

  /// No description provided for @stationsRouteSourceDisruptionLocal.
  ///
  /// In en, this message translates to:
  /// **'Disruption-aware reroute (local)'**
  String get stationsRouteSourceDisruptionLocal;

  /// No description provided for @stationsRouteSourceRpcAlerts.
  ///
  /// In en, this message translates to:
  /// **'Supabase RPC (service alerts active)'**
  String get stationsRouteSourceRpcAlerts;

  /// No description provided for @stationsRouteSourceRpc.
  ///
  /// In en, this message translates to:
  /// **'Supabase RPC'**
  String get stationsRouteSourceRpc;

  /// No description provided for @stationsRouteSourceDisruptionGraph.
  ///
  /// In en, this message translates to:
  /// **'Disruption-aware route graph'**
  String get stationsRouteSourceDisruptionGraph;

  /// No description provided for @stationsRouteSourceGraphCache.
  ///
  /// In en, this message translates to:
  /// **'Supabase route graph cache (RPC unavailable)'**
  String get stationsRouteSourceGraphCache;

  /// No description provided for @stationsDisruptionKjTitle.
  ///
  /// In en, this message translates to:
  /// **'Peak crowd control on Kelana Jaya Line'**
  String get stationsDisruptionKjTitle;

  /// No description provided for @stationsDisruptionKjDetail.
  ///
  /// In en, this message translates to:
  /// **'Expect longer dwell times during rush-hour boarding.'**
  String get stationsDisruptionKjDetail;

  /// No description provided for @stationsDisruptionAgTitle.
  ///
  /// In en, this message translates to:
  /// **'Platform congestion on Ampang Line'**
  String get stationsDisruptionAgTitle;

  /// No description provided for @stationsDisruptionAgDetail.
  ///
  /// In en, this message translates to:
  /// **'Midday crowding may slow boarding and transfers.'**
  String get stationsDisruptionAgDetail;

  /// No description provided for @stationsDisruptionMrTitle.
  ///
  /// In en, this message translates to:
  /// **'Reduced Monorail frequency'**
  String get stationsDisruptionMrTitle;

  /// No description provided for @stationsDisruptionMrDetail.
  ///
  /// In en, this message translates to:
  /// **'Late-evening headways are wider than usual.'**
  String get stationsDisruptionMrDetail;

  /// No description provided for @stationsMissingGtfsStopId.
  ///
  /// In en, this message translates to:
  /// **'Selected station is missing a GTFS stop id.'**
  String get stationsMissingGtfsStopId;

  /// No description provided for @stationsNoCodeForReport.
  ///
  /// In en, this message translates to:
  /// **'No station code found for reporting.'**
  String get stationsNoCodeForReport;

  /// No description provided for @stationsTooFarFromStation.
  ///
  /// In en, this message translates to:
  /// **'You are {distance}m from this station. Please move within 500m for accurate reporting.'**
  String stationsTooFarFromStation(int distance);

  /// No description provided for @stationsEnableLocationToReport.
  ///
  /// In en, this message translates to:
  /// **'Enable location to verify proximity before reporting crowd levels.'**
  String get stationsEnableLocationToReport;

  /// No description provided for @stationsReportCrowdLevel.
  ///
  /// In en, this message translates to:
  /// **'Report Crowd Level'**
  String get stationsReportCrowdLevel;

  /// No description provided for @stationsStationCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Station Code'**
  String get stationsStationCodeLabel;

  /// No description provided for @stationsHowCrowdedNow.
  ///
  /// In en, this message translates to:
  /// **'How crowded is it now?'**
  String get stationsHowCrowdedNow;

  /// No description provided for @stationsCrowdLevelOption.
  ///
  /// In en, this message translates to:
  /// **'L{level} {label}'**
  String stationsCrowdLevelOption(int level, String label);

  /// No description provided for @stationsMoveCloser.
  ///
  /// In en, this message translates to:
  /// **'Move Closer to Submit'**
  String get stationsMoveCloser;

  /// No description provided for @stationsSubmitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get stationsSubmitReport;

  /// No description provided for @stationsReportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Thanks. Crowd report submitted for {stopId}.'**
  String stationsReportSubmitted(String stopId);

  /// No description provided for @stationsReportSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit report: {error}'**
  String stationsReportSubmitFailed(String error);

  /// No description provided for @stationsSuggestedRoute.
  ///
  /// In en, this message translates to:
  /// **'Suggested Route'**
  String get stationsSuggestedRoute;

  /// No description provided for @stationsRouteSummary.
  ///
  /// In en, this message translates to:
  /// **'{originName} ({originStopId}) -> {destinationName} ({destinationStopId})'**
  String stationsRouteSummary(String originName, String originStopId,
      String destinationName, String destinationStopId);

  /// No description provided for @stationsDepartAt.
  ///
  /// In en, this message translates to:
  /// **'Depart: {time}'**
  String stationsDepartAt(String time);

  /// No description provided for @stationsArriveAt.
  ///
  /// In en, this message translates to:
  /// **'Arrive: {time}'**
  String stationsArriveAt(String time);

  /// No description provided for @stationsBaseEta.
  ///
  /// In en, this message translates to:
  /// **'Base ETA ~ {duration}'**
  String stationsBaseEta(String duration);

  /// No description provided for @stationsCrowdEta.
  ///
  /// In en, this message translates to:
  /// **'Crowd ETA ~ {duration}'**
  String stationsCrowdEta(String duration);

  /// No description provided for @stationsForecastConfidenceChip.
  ///
  /// In en, this message translates to:
  /// **'Forecast confidence {percent}'**
  String stationsForecastConfidenceChip(String percent);

  /// No description provided for @stationsTripCrowd.
  ///
  /// In en, this message translates to:
  /// **'Trip Crowd: {label}'**
  String stationsTripCrowd(String label);

  /// No description provided for @stationsStopCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stop} other{{count} stops}}'**
  String stationsStopCount(int count);

  /// No description provided for @stationsReroutedAroundDisruption.
  ///
  /// In en, this message translates to:
  /// **'Rerouted around disruption'**
  String get stationsReroutedAroundDisruption;

  /// No description provided for @stationsRouteSource.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String stationsRouteSource(String source);

  /// No description provided for @stationsServiceAlerts.
  ///
  /// In en, this message translates to:
  /// **'Service alerts: {alerts}'**
  String stationsServiceAlerts(String alerts);

  /// No description provided for @stationsWalkToOrigin.
  ///
  /// In en, this message translates to:
  /// **'Walk to origin: {distance}'**
  String stationsWalkToOrigin(String distance);

  /// No description provided for @stationsNoRouteSegments.
  ///
  /// In en, this message translates to:
  /// **'No route segments available.'**
  String get stationsNoRouteSegments;

  /// No description provided for @stationsSegmentTimeRange.
  ///
  /// In en, this message translates to:
  /// **'{depart} to {arrive} - {label}'**
  String stationsSegmentTimeRange(String depart, String arrive, String label);

  /// No description provided for @stationsForecastConfidence.
  ///
  /// In en, this message translates to:
  /// **'Forecast confidence: {percent}'**
  String stationsForecastConfidence(String percent);

  /// No description provided for @stationsBoardingTip.
  ///
  /// In en, this message translates to:
  /// **'Coach/platform tip: {tip}'**
  String stationsBoardingTip(String tip);

  /// No description provided for @stationsServiceAlert.
  ///
  /// In en, this message translates to:
  /// **'Service alert: {note}'**
  String stationsServiceAlert(String note);

  /// No description provided for @stationsIncludesWaitingTime.
  ///
  /// In en, this message translates to:
  /// **'Includes approx. {minutes} min waiting time'**
  String stationsIncludesWaitingTime(int minutes);

  /// No description provided for @stationsForecastReasonClosed.
  ///
  /// In en, this message translates to:
  /// **'Train service is currently outside operating hours.'**
  String get stationsForecastReasonClosed;

  /// No description provided for @stationsForecastReasonRecentReports.
  ///
  /// In en, this message translates to:
  /// **'recent rider reports'**
  String get stationsForecastReasonRecentReports;

  /// No description provided for @stationsForecastReasonHourlyForecast.
  ///
  /// In en, this message translates to:
  /// **'hourly ridership forecast'**
  String get stationsForecastReasonHourlyForecast;

  /// No description provided for @stationsForecastReasonSimulation.
  ///
  /// In en, this message translates to:
  /// **'10-minute simulation fallback'**
  String get stationsForecastReasonSimulation;

  /// No description provided for @stationsForecastReasonOfflineFallback.
  ///
  /// In en, this message translates to:
  /// **'offline fallback estimate'**
  String get stationsForecastReasonOfflineFallback;

  /// No description provided for @stationsForecastReasonTransferWait.
  ///
  /// In en, this message translates to:
  /// **'transfer wait included'**
  String get stationsForecastReasonTransferWait;

  /// No description provided for @stationsForecastReasonPeakLoad.
  ///
  /// In en, this message translates to:
  /// **'peak-load conditions likely'**
  String get stationsForecastReasonPeakLoad;

  /// No description provided for @stationsForecastReasonStandingDemand.
  ///
  /// In en, this message translates to:
  /// **'standing demand likely'**
  String get stationsForecastReasonStandingDemand;

  /// No description provided for @stationsBoardingTipTransfer.
  ///
  /// In en, this message translates to:
  /// **'Follow interchange signs promptly at {station}.'**
  String stationsBoardingTipTransfer(String station);

  /// No description provided for @stationsBoardingTipMiddleRear.
  ///
  /// In en, this message translates to:
  /// **'Board middle-rear coach for a faster transfer at {station}.'**
  String stationsBoardingTipMiddleRear(String station);

  /// No description provided for @stationsBoardingTipNearDoors.
  ///
  /// In en, this message translates to:
  /// **'Board near the doors for a quicker exit at {station}.'**
  String stationsBoardingTipNearDoors(String station);

  /// No description provided for @stationsBoardingTipPlatformSigns.
  ///
  /// In en, this message translates to:
  /// **'Follow platform signs toward {station}-bound service.'**
  String stationsBoardingTipPlatformSigns(String station);

  /// No description provided for @stationsSegmentTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer from {from} to {to} ({base} base, ~{forecast} forecast)'**
  String stationsSegmentTransfer(
      String from, String to, String base, String forecast);

  /// No description provided for @stationsSegmentRide.
  ///
  /// In en, this message translates to:
  /// **'Take {route} from {from} to {to} ({base} base, ~{forecast} forecast)'**
  String stationsSegmentRide(
      String route, String from, String to, String base, String forecast);

  /// No description provided for @stationsFareTotal.
  ///
  /// In en, this message translates to:
  /// **'Fare RM {amount}'**
  String stationsFareTotal(String amount);

  /// No description provided for @stationsFareTicketCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 ticket} other{{count} tickets}}'**
  String stationsFareTicketCount(int count);

  /// No description provided for @stationsSegmentFare.
  ///
  /// In en, this message translates to:
  /// **'RM {amount}'**
  String stationsSegmentFare(String amount);

  /// No description provided for @arrivalsNextTrain.
  ///
  /// In en, this message translates to:
  /// **'NEXT TRAIN'**
  String get arrivalsNextTrain;

  /// No description provided for @arrivalsSignalLost.
  ///
  /// In en, this message translates to:
  /// **'SIGNAL LOST — TAP TO RETRY'**
  String get arrivalsSignalLost;

  /// No description provided for @arrivalsNoScheduledTrains.
  ///
  /// In en, this message translates to:
  /// **'NO SCHEDULED TRAINS'**
  String get arrivalsNoScheduledTrains;

  /// No description provided for @arrivalsOfflineStaticSchedule.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE — STATIC SCHEDULE'**
  String get arrivalsOfflineStaticSchedule;

  /// No description provided for @arrivalsGtfsStaticSchedule.
  ///
  /// In en, this message translates to:
  /// **'GTFS STATIC SCHEDULE'**
  String get arrivalsGtfsStaticSchedule;

  /// No description provided for @arrivalsToDestination.
  ///
  /// In en, this message translates to:
  /// **'TO {destination}'**
  String arrivalsToDestination(String destination);

  /// No description provided for @arrivalsArriving.
  ///
  /// In en, this message translates to:
  /// **'ARRIVING'**
  String get arrivalsArriving;

  /// No description provided for @arrivalsMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String arrivalsMinutesShort(int minutes);

  /// No description provided for @crowdBoardTitle.
  ///
  /// In en, this message translates to:
  /// **'Crowd Pulse'**
  String get crowdBoardTitle;

  /// No description provided for @crowdBoardSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search station name'**
  String get crowdBoardSearchHint;

  /// No description provided for @crowdBoardLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get crowdBoardLoading;

  /// No description provided for @crowdBoardEmpty.
  ///
  /// In en, this message translates to:
  /// **'No station crowd data available yet.'**
  String get crowdBoardEmpty;

  /// No description provided for @crowdBoardFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get crowdBoardFilterAll;

  /// No description provided for @crowdBoardLevelClosed.
  ///
  /// In en, this message translates to:
  /// **'{label} · Closed'**
  String crowdBoardLevelClosed(String label);

  /// No description provided for @forecastTitle.
  ///
  /// In en, this message translates to:
  /// **'Crowd Outlook'**
  String get forecastTitle;

  /// No description provided for @forecastNoStations.
  ///
  /// In en, this message translates to:
  /// **'No stations found.'**
  String get forecastNoStations;

  /// No description provided for @forecastStationLabel.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get forecastStationLabel;

  /// No description provided for @forecastLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load crowd forecast: {error}'**
  String forecastLoadFailed(String error);

  /// No description provided for @forecastEmpty.
  ///
  /// In en, this message translates to:
  /// **'No forecast yet for this station.'**
  String get forecastEmpty;

  /// No description provided for @forecastClosingHoursBody.
  ///
  /// In en, this message translates to:
  /// **'Train service is currently closed. Forecasts resume from 6:00 AM.'**
  String get forecastClosingHoursBody;

  /// No description provided for @forecastLevel1Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Almost empty with seats widely available'**
  String get forecastLevel1Subtitle;

  /// No description provided for @forecastLevel2Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Comfortable ride with space to spare'**
  String get forecastLevel2Subtitle;

  /// No description provided for @forecastLevel3Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Moderate traffic with routine standing demand'**
  String get forecastLevel3Subtitle;

  /// No description provided for @forecastLevel4Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Heavy crowding with slower boarding likely'**
  String get forecastLevel4Subtitle;

  /// No description provided for @forecastLevel5Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Crowded conditions across the platform and carriage'**
  String get forecastLevel5Subtitle;

  /// No description provided for @forecastUnknownLevelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No valid occupancy level'**
  String get forecastUnknownLevelSubtitle;

  /// No description provided for @forecastExplanationClosed.
  ///
  /// In en, this message translates to:
  /// **'Train service is outside operating hours. Stations are shown as unavailable until 6:00 AM.'**
  String get forecastExplanationClosed;

  /// No description provided for @forecastExplanationRecentReports.
  ///
  /// In en, this message translates to:
  /// **'based on recent rider reports'**
  String get forecastExplanationRecentReports;

  /// No description provided for @forecastExplanationHourlyForecast.
  ///
  /// In en, this message translates to:
  /// **'based on hourly ridership forecasts'**
  String get forecastExplanationHourlyForecast;

  /// No description provided for @forecastExplanationSimulation.
  ///
  /// In en, this message translates to:
  /// **'using 10-minute simulation fallback'**
  String get forecastExplanationSimulation;

  /// No description provided for @forecastExplanationOfflineFallback.
  ///
  /// In en, this message translates to:
  /// **'using offline fallback estimate'**
  String get forecastExplanationOfflineFallback;

  /// No description provided for @forecastReasonVeryLowOccupancy.
  ///
  /// In en, this message translates to:
  /// **'very low expected occupancy'**
  String get forecastReasonVeryLowOccupancy;

  /// No description provided for @forecastReasonComfortableSpace.
  ///
  /// In en, this message translates to:
  /// **'comfortable space still available'**
  String get forecastReasonComfortableSpace;

  /// No description provided for @forecastReasonModerateStanding.
  ///
  /// In en, this message translates to:
  /// **'moderate standing demand likely'**
  String get forecastReasonModerateStanding;

  /// No description provided for @forecastLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String forecastLevelLabel(int level);

  /// No description provided for @forecastLevelClosed.
  ///
  /// In en, this message translates to:
  /// **'Level {level} · Closed'**
  String forecastLevelClosed(int level);

  /// No description provided for @forecastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated: {time}'**
  String forecastUpdated(String time);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ms', 'ta', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ms':
      return AppLocalizationsMs();
    case 'ta':
      return AppLocalizationsTa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
