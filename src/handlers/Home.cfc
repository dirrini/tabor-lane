component {

    function index( event, rc, prc ) {
        prc.page = "home";
        prc.pageTitle = $r( "meta.title" );
        event.setView( "home/index" );
    }

}

