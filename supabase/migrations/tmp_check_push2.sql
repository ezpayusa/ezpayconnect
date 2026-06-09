SELECT user_id, endpoint, p256dh, auth, created_at 
FROM push_subscriptions 
ORDER BY created_at DESC 
LIMIT 1;
