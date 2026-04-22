# Smart Commuter Assistant+ 🚆🇲🇾

A modern Flutter app designed for Malaysian public transport users to predict train arrival times, estimate crowd levels, and optimize routes.

## Features

- **Train Arrival Predictions**: Real-time arrival times with crowd level indicators
- **Route Planning**: Intelligent route optimization with multiple options
- **Station Details**: Live updates on upcoming trains and crowd levels
- **Zoomable Rail Map**: Full-screen Klang Valley rail map with pinch and scroll zoom
- **User Profiles**: Personalized settings and favorite routes
- **Malaysian Theme**: Material 3 design inspired by the Malaysian flag colors

## Project Structure

```
lib/
├── main.dart                    # App entry point with Malaysian-themed Material 3
├── screens/
│   ├── home_screen.dart        # Main dashboard with predictions and quick actions
│   ├── route_planner.dart      # Route planning with origin/destination input
│   ├── station_details.dart    # Station info with upcoming trains
│   ├── map_view.dart          # Zoomable static Klang Valley rail map
│   └── profile_screen.dart     # User settings and preferences
├── widgets/
│   ├── prediction_card.dart    # Reusable card for train predictions
│   ├── crowd_indicator.dart    # Visual crowd level indicator
│   ├── route_input.dart       # Origin/destination input widget
│   └── app_page_title.dart    # Shared branded page title widget
├── models/
│   ├── train_prediction.dart   # Train arrival prediction data model
│   └── route_info.dart        # Route information data model
└── services/
    ├── api_service.dart        # Mock API service for train data
    ├── notification_service.dart # Local notifications management
    └── storage_service.dart    # Local storage for favorites and preferences
```

## Design Theme

The app uses a Malaysian flag-inspired color scheme:
- **Primary (Deep Blue)**: #010066
- **Secondary (Bright Red)**: #C8102E  
- **Tertiary (Bright Yellow)**: #FFD100
- **Background**: #F5F5F5

## Getting Started

1. **Prerequisites**
   - Flutter SDK (>=3.0.0)
   - Dart SDK
   - Android Studio or VS Code

2. **Installation**
   ```bash
   # Clone or download the project
   cd "Smart Commuter Assistant+"
   
   # Get dependencies
   flutter pub get
   
   # Run the app
   flutter run
   ```

3. **Development Setup**
   - Uncomment dependencies in `pubspec.yaml` as needed
   - Replace mock API calls with real endpoints
   - Add Google Maps API key for map functionality
   - Configure local notifications

4. **Supabase Database Setup**
   - Populate `public.train_stops_kl` first.
   - Run `lib/PythonScript/stop_catalog_setup.sql`.
   - Run `lib/PythonScript/route_connections_setup.sql`.
   - Run `lib/PythonScript/find_route_rpc_setup.sql`.
   - Run `lib/PythonScript/crowd_reports_setup.sql`.
   - Run `lib/PythonScript/crowd_forecast_setup.sql`.
   - Optional seed: `lib/PythonScript/randomized_crowd_predictions_seed.sql`

## Current Implementation Status

### ✅ Completed
- Complete Flutter project structure
- Malaysian-themed Material 3 UI
- Navigation between all screens
- Mock data and services
- Responsive design for Android devices

### 🚧 TODO (Future Development)
- Integrate real Malaysian transport APIs
- Add Google Maps SDK
- Implement local notifications
- Add state management (Provider/Riverpod)
- Implement offline data caching
- Add unit and widget tests
- Integrate with real-time transport data

## Mock Data

The app currently uses mock data for development:
- Sample train predictions with random arrival times
- Mock route calculations between stations
- Simulated crowd level data
- Placeholder station information

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is created for educational and development purposes.

## Contact

For questions or suggestions, please reach out to the development team.

---

**Made with ❤️ for Malaysian commuters**
