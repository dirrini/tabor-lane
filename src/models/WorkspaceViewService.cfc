component singleton {
    void function render( required any event, required struct prc, required string view ) {
        var headers = getHttpRequestData().headers ?: {};
        var isHtmxRequest =
            compareNoCase( headers[ "HX-Request" ] ?: "", "true" ) == 0
            && compareNoCase( headers[ "HX-History-Restore-Request" ] ?: "", "true" ) != 0;
        arguments.prc.isHtmxRequest = isHtmxRequest;
        if ( isHtmxRequest ) {
            arguments.event.setView( view = arguments.view, noLayout = true );
            return;
        }
        arguments.event.setView( view = arguments.view, layout = "Workspace" );
    }
}
