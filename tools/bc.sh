#!/system/bin/sh
# Delivers the plugin's scheduled-notification broadcast from within the app uid,
# which is required because ScheduledNotificationReceiver is exported=false.
am broadcast --user 0 -n com.claimtracker.claim_tracker/com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver --es notificationDetails '{"id":3,"title":"تذكير متابعة مطالبة","body":"لديك مطالبة تستحق المتابعة الآن.","channelId":"claim_reminders","payload":"claim:3","priority":2,"style":"Default","styleInformation":{"type":"DefaultStyleInformation","htmlFormatTitle":false,"htmlFormatBody":false}}'
