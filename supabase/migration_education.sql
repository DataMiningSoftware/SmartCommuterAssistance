-- ============================================================
-- Smart Commuter Assistant+ — Education Migration
-- Station lore (reference reading, with citations) + quiz attempt
-- log for the mastery / "independence" signal.
-- ============================================================

-- ------------------------------------------------------------------
-- STATION LORE
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.station_lore (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  station_id   TEXT NOT NULL,
  station_name TEXT NOT NULL,
  opening_year INTEGER,
  line_history TEXT,
  facts        JSONB,
  context      TEXT,
  source_name  TEXT,
  source_url   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (station_id)
);

-- ------------------------------------------------------------------
-- QUIZ ATTEMPTS (mastery signal)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.quiz_attempts (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_kind TEXT NOT NULL
                  CHECK (question_kind IN ('station_identify', 'route_knowledge')),
  station_id    TEXT,
  route_id      TEXT,
  correct       BOOLEAN NOT NULL,
  used_hint     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quiz_attempts_user ON public.quiz_attempts (user_id, created_at DESC);

-- Mastery / independence stats for the visible "you no longer need us" meter.
CREATE OR REPLACE FUNCTION public.get_mastery_stats()
RETURNS TABLE (
  stations_learned BIGINT,
  total_attempts   BIGINT,
  correct_attempts BIGINT,
  accuracy_pct     NUMERIC,
  no_hint_correct  BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COUNT(DISTINCT station_id) FILTER (WHERE correct) AS stations_learned,
    COUNT(*)::BIGINT AS total_attempts,
    COUNT(*) FILTER (WHERE correct)::BIGINT AS correct_attempts,
    CASE WHEN COUNT(*) = 0 THEN 0
         ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE correct) / COUNT(*), 1)
    END AS accuracy_pct,
    COUNT(*) FILTER (WHERE correct AND NOT used_hint)::BIGINT AS no_hint_correct
  FROM public.quiz_attempts
  WHERE user_id = auth.uid();
$$;

ALTER TABLE public.station_lore ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_attempts ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------
-- SEED: curated lore for major stations (expandable later).
-- source_url is kept general where a specific page isn't guaranteed.
-- ------------------------------------------------------------------
INSERT INTO public.station_lore
  (station_id, station_name, opening_year, line_history, facts, context, source_name, source_url)
VALUES
  ('KJ15', 'KL Sentral', 2001, 'Opened as the main rail transport hub replacing the old Kuala Lumpur railway station.',
   '["KL Sentral is the largest railway station in Malaysia.","It connects KTM, LRT Kelana Jaya, the KLIA Transit/Express, and the monorail.","The station was built on the site of the former Keretapi Tanah Melayu marshalling yard."]',
   'A modern transit interchange and gateway to the city.', 'Wikipedia', 'https://en.wikipedia.org/wiki/KL_Sentral'),
  ('KJ13', 'Masjid Jamek', 1996, 'LRT station serving the historic Masjid Jamek mosque, an interchange between the Kelana Jaya and Ampang lines.',
   '["Named after the Jamek Mosque at the confluence of the Klang and Gombak rivers.","It is one of the oldest LRT interchanges in the network."]',
   'Historic mosque and riverside interchange.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('KJ14', 'Pasar Seni', 1998, 'LRT Kelana Jaya line station near Central Market and the arts district.',
   '["Pasar Seni means \"Art Market\" in Malay.","It serves the Central Market and nearby Chinatown (Petaling Street)."]',
   'Arts, heritage and street food hub.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('MR6', 'Bukit Bintang', 2003, 'KL Monorail station in the heart of the shopping and entertainment district.',
   '["Bukit Bintang is Kuala Lumpur''s main shopping belt.","The monorail station links to the MRT via a pedestrian walkway."]',
   'Retail, nightlife and food district.', 'Wikipedia', 'https://en.wikipedia.org/wiki/Bukit_Bintang_Monorail_station'),
  ('KJ10', 'KLCC', 1998, 'LRT Kelana Jaya station beneath the Petronas Twin Towers.',
   '["KLCC stands for Kuala Lumpur City Centre.","It serves the Petronas Towers and Suria KLCC shopping centre."]',
   'Iconic towers and business district.', 'Wikipedia', 'https://en.wikipedia.org/wiki/KLCC_LRT_station'),
  ('AG18', 'Ampang', 1996, 'Eastern terminus of the Ampang line, one of the first LRT lines in the country.',
   '["The Ampang LRT line opened in 1996.","Ampang is the eastern terminus of the line."]',
   'Eastern suburb and line terminus.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('AG10', 'Wangsa Maju', 1996, 'LRT Ampang/Sri Petaling line station serving a dense residential district.',
   '["Wangsa Maju is a large residential and student area.","It is a key commuter station on the Ampang line."]',
   'Dense commuter suburb.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('SP12', 'Sri Petaling', 1996, 'Namesake station of the Sri Petaling line branch.',
   '["The Sri Petaling line branches from the Ampang line at Chan Sow Lin.","The area is known for the Bukit Jalil sports complex nearby."]',
   'Line branch and sports-venue access.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('SP31', 'Putra Heights', 2016, 'Interchange terminus connecting the Kelana Jaya and Sri Petaling lines.',
   '["Putra Heights is a major interchange terminus in the south.","It links the LRT Kelana Jaya and Sri Petaling lines."]',
   'Southern interchange terminus.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('KG34', 'Kajang', 2017, 'Southern terminus of the MRT Kajang line.',
   '["Kajang is famous for its satay.","The MRT Kajang line opened fully in 2017."]',
   'MRT terminus and satay town.', 'Wikipedia', 'https://en.wikipedia.org/wiki/Kajang_MRT_station'),
  ('PY01', 'Sungai Buloh', 2017, 'MRT Putrajaya line station and interchange with KTM.',
   '["Sungai Buloh is a major interchange between MRT and KTM.","It served as the northern terminus of the MRT Kajang line before the Putrajaya line."]',
   'Northern interchange with KTM.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('PY21', 'Tun Razak Exchange', 2023, 'MRT Putrajaya line station in the TRX financial district.',
   '["TRX is an interchange between the MRT Kajang and Putrajaya lines.","It serves the Tun Razak Exchange financial district."]',
   'Financial district interchange.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('PY20', 'Merdeka', 2023, 'MRT Putrajaya line station near Merdeka 118 and the Merdeka Stadium.',
   '["The station is adjacent to Merdeka 118, one of the world''s tallest towers.","It is near the historic Merdeka Stadium."]',
   'Historic independence site.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('KG09', 'Mutiara Damansara', 2017, 'MRT Kajang line station serving a commercial and retail cluster.',
   '["Mutiara Damansara serves major malls and office towers.","It is a popular interchange for buses into Damansara."]',
   'Commercial and retail cluster.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('KG08', 'Bandar Utama', 2017, 'MRT Kajang line station in the Bandar Utama township.',
   '["Bandar Utama station serves the 1 Utama shopping centre.","It is a key station in the Petaling Jaya area."]',
   'Shopping and township hub.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('KJ31', 'USJ 7', 2016, 'LRT Kelana Jaya station in the USJ township.',
   '["USJ 7 serves the USJ residential township.","It is a busy commuter station in Subang Jaya."]',
   'Residential commuter station.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('SBK07', 'Subang Jaya', 1995, 'KTM Komuter and LRT interchange serving the Subang Jaya township.',
   '["Subang Jaya is a major KTM and LRT interchange.","It connects the Port Klang line with the LRT Kelana Jaya line."]',
   'KTM/LRT interchange.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('MR1', 'KL Sentral Monorail', 2003, 'Monorail terminus linked to the KL Sentral interchange.',
   '["The monorail terminus links to KL Sentral via a covered walkway.","The KL Monorail opened in 2003."]',
   'Monorail gateway at KL Sentral.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('AG2', 'Chan Sow Lin', 1996, 'Interchange where the Ampang and Sri Petaling lines meet.',
   '["Chan Sow Lin is where the Sri Petaling line branches from the Ampang line.","It is a key east-side interchange."]',
   'East-side line branching point.', 'Rapid KL', 'https://myrapid.com.my/'),
  ('PY22', 'Conlay', 2023, 'MRT Putrajaya line station in the Conlay area.',
   '["Conlay station serves a mixed commercial and residential area.","It is on the MRT Putrajaya line."]',
   'Inner-city Putrajaya line station.', 'Rapid KL', 'https://myrapid.com.my/')
ON CONFLICT (station_id) DO NOTHING;
