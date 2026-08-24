from crowd_service import CrowdService

CrowdService()._get_supabase().rpc("snapshot_daily_blend").execute()
