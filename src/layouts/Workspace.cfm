<cfscript>
    currentLocale = getFWLocale();
    htmlLanguage = currentLocale == "pt_BR" ? "pt-BR" : "en";
    pageName = prc.page ?: "";
    pageTitle = prc.pageTitle ?: $r( "meta.title" );
</cfscript>
<cfoutput>
<!doctype html>
<html lang="#htmlLanguage#">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="theme-color" content="##f8f4f1">
    <meta name="description" content="#encodeForHTMLAttribute( $r( "meta.description" ) )#">
    <meta name="htmx-config" content='{"historyRestoreAsHxRequest":false}'>
    <title>#encodeForHTML( pageTitle )#</title>
    <link rel="icon" href="/resources/favicon.svg" type="image/svg+xml">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=Manrope:wght@500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="/resources/css/app.css">
    <script src="https://cdn.jsdelivr.net/npm/htmx.org@2.0.10/dist/htmx.min.js" integrity="sha384-H5SrcfygHmAuTDZphMHqBJLc3FhssKjG7w/CeCpFReSfwBWDTKpkzPP8c+cLsK+V" crossorigin="anonymous" defer></script>
    <script src="/resources/js/app.js" defer></script>
</head>
<body class="page-#encodeForHTMLAttribute( pageName )#">
    <main class="workspace-shell" data-workspace-shell hx-history="false">
        <button class="workspace-menu-toggle" type="button" data-workspace-menu-toggle aria-label="#$r( 'app.menu.open' )#" aria-expanded="false"><svg class="icon"><use href="/resources/icons.svg##menu"></use></svg></button>
        #view( "app/_sidebar" )#
        <button class="workspace-menu-backdrop" type="button" data-workspace-menu-close aria-label="#$r( 'app.menu.close' )#"></button>
        #view()#
    </main>
</body>
</html>
</cfoutput>
