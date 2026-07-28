component {

    property name="i18n" inject="i18n@cbi18n";
    property name="resourceService" inject="resourceService@cbi18n";

    function preProcess( event, interceptData, buffer, rc, prc ) {
        resourceService.loadBundle(
            rbFile = "includes/i18n/main",
            rbLocale = i18n.getFWLocale(),
            rbAlias = "default"
        );
    }

}
