component {

    function change( event, rc, prc ) {
        var allowedLocales = {
            "en_US" = true,
            "pt_BR" = true
        };
        var requestedLocale = rc.locale ?: "en_US";

        if ( structKeyExists( allowedLocales, requestedLocale ) ) {
            setFWLocale( requestedLocale );
        }

        relocate( uri = "/" );
    }

}

