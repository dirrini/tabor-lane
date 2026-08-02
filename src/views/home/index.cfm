<cfoutput>
<header class="site-header" data-header>
    <div class="shell nav-wrap">
        <a class="brand" href="/" aria-label="Tabor Lane">
            <span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span>
            <span class="brand-name">Tabor<span>Lane</span></span>
        </a>

        <button class="nav-toggle" type="button" aria-label="Toggle navigation" aria-expanded="false" data-nav-toggle>
            <span></span><span></span>
        </button>

        <nav class="main-nav" data-nav>
            <a href="##product">#$r( "nav.product" )#</a>
            <a href="##solutions">#$r( "nav.solutions" )#</a>
            <a href="##pricing">#$r( "nav.pricing" )#</a>
        </nav>

        <div class="nav-actions">
            <div class="language-switch" aria-label="Language">
                <a href="/locale/en_US" class="#getFWLocale() == 'en_US' ? 'active' : ''#" lang="en">EN</a>
                <span>/</span>
                <a href="/locale/pt_BR" class="#getFWLocale() == 'pt_BR' ? 'active' : ''#" lang="pt-BR">PT</a>
            </div>
            <a class="text-link login-link" href="/login">#$r( "nav.login" )#</a>
            <a class="button button-small button-dark" href="/signup">#$r( "nav.signup" )#</a>
        </div>
    </div>
</header>

<main>
    <section class="hero" id="product">
        <div class="hero-glow hero-glow-one"></div>
        <div class="hero-glow hero-glow-two"></div>
        <div class="shell hero-copy">
            <p class="eyebrow"><span></span>#$r( "hero.eyebrow" )#</p>
            <h1>#$r( "hero.titleA" )#<br><em>#$r( "hero.titleB" )#</em></h1>
            <p class="hero-lead">#$r( "hero.body" )#</p>
            <div class="hero-actions">
                <a class="button button-primary" href="/signup">
                    #$r( "hero.primary" )# <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg>
                </a>
                <a class="button button-ghost" href="/app">
                    <span class="play-dot" aria-hidden="true"><svg class="icon"><use href="/resources/icons.svg##play"></use></svg></span> #$r( "hero.secondary" )#
                </a>
            </div>
            <p class="hero-note"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg> #$r( "hero.note" )#</p>
        </div>

        <div class="shell board-stage" aria-label="#encodeForHTMLAttribute( $r( 'board.title' ) )#">
            <div class="board-window">
                <div class="board-toolbar">
                    <div>
                        <span class="board-logo"><b></b><b></b><b></b></span>
                        <strong>#$r( "board.title" )#</strong>
                        <span class="toolbar-star"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##star"></use></svg></span>
                    </div>
                    <div class="board-people">
                        <span class="presence"></span>
                        <small>#$r( "board.updated" )#</small>
                        <i class="avatar avatar-a">MA</i>
                        <i class="avatar avatar-b">JL</i>
                        <i class="avatar avatar-c">RK</i>
                        <button class="icon-only" type="button" aria-label="More options"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##more"></use></svg></button>
                    </div>
                </div>

                <div class="kanban-grid">
                    <article class="kanban-column">
                        <header><span class="column-dot dot-sand"></span><strong>#$r( "board.col1" )#</strong><b>2</b><i><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##more"></use></svg></i></header>
                        <div class="demo-card">
                            <span class="card-label label-violet">#$r( "board.design" )#</span>
                            <h3>#$r( "board.card1" )#</h3>
                            <div class="card-meta"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##list-checks"></use></svg> 3/5</span><i class="avatar avatar-a">MA</i></div>
                        </div>
                        <div class="demo-card">
                            <span class="card-label label-green">#$r( "board.marketing" )#</span>
                            <h3>#$r( "board.card2" )#</h3>
                            <div class="card-meta"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg> 18 Sep</span><i class="avatar avatar-b">JL</i></div>
                        </div>
                        <button class="add-card" type="button"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r( "app.card.addInLane" )#</button>
                    </article>

                    <article class="kanban-column">
                        <header><span class="column-dot dot-blue"></span><strong>#$r( "board.col2" )#</strong><b>2</b><em>#$r( "board.wip" )#</em><i><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##more"></use></svg></i></header>
                        <div class="demo-card card-raised">
                            <span class="card-label label-blue">#$r( "board.ops" )#</span>
                            <h3>#$r( "board.card3" )#</h3>
                            <p>API · Webhooks · Forms</p>
                            <div class="card-meta"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##paperclip"></use></svg> 2 &nbsp; <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg> 20 Sep</span><i class="avatar avatar-c">RK</i></div>
                        </div>
                        <div class="demo-card">
                            <div class="blocked"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg> #$r( "board.blocked" )#</div>
                            <h3>#$r( "board.card4" )#</h3>
                            <div class="card-meta"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##list-checks"></use></svg> 4 &nbsp; <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##paperclip"></use></svg> 5</span><i class="avatar avatar-a">MA</i></div>
                        </div>
                        <button class="add-card" type="button"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r( "app.card.addInLane" )#</button>
                    </article>

                    <article class="kanban-column">
                        <header><span class="column-dot dot-amber"></span><strong>#$r( "board.col3" )#</strong><b>1</b><i><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##more"></use></svg></i></header>
                        <div class="demo-card">
                            <span class="card-label label-green">#$r( "board.marketing" )#</span>
                            <h3>#$r( "board.card5" )#</h3>
                            <div class="card-meta"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##list-checks"></use></svg> 7/8</span><span class="tiny-avatars"><i class="avatar avatar-b">JL</i><i class="avatar avatar-c">RK</i></span></div>
                        </div>
                        <button class="add-card" type="button"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r( "app.card.addInLane" )#</button>
                    </article>

                    <article class="kanban-column">
                        <header><span class="column-dot dot-green"></span><strong>#$r( "board.col4" )#</strong><b>1</b><i><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##more"></use></svg></i></header>
                        <div class="demo-card done-card">
                            <span class="complete-check"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg></span>
                            <div>
                                <h3>#$r( "board.card6" )#</h3>
                                <div class="card-meta"><span>12 Sep</span><i class="avatar avatar-b">JL</i></div>
                            </div>
                        </div>
                        <button class="add-card" type="button"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r( "app.card.addInLane" )#</button>
                    </article>
                </div>
            </div>
        </div>
    </section>

    <section class="trust-strip">
        <div class="shell">
            <p>#$r( "trust.title" )#</p>
            <div class="trust-list">
                <span><b><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##board"></use></svg></b> #$r( "trust.item1" )#</span>
                <span><b><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##columns"></use></svg></b> #$r( "trust.item2" )#</span>
                <span><b><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chart"></use></svg></b> #$r( "trust.item3" )#</span>
                <span><b><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##link"></use></svg></b> #$r( "trust.item4" )#</span>
                <span><b><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg></b> #$r( "trust.item5" )#</span>
            </div>
        </div>
    </section>

    <section class="features-section section" id="solutions">
        <div class="shell">
            <div class="section-heading">
                <div>
                    <p class="eyebrow"><span></span>#$r( "features.eyebrow" )#</p>
                    <h2>#$r( "features.title" )#</h2>
                </div>
                <p>#$r( "features.body" )#</p>
            </div>

            <div class="feature-grid">
                <article class="feature-card feature-flow">
                    <div class="feature-icon"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chart"></use></svg></div>
                    <h3>#$r( "features.flow.title" )#</h3>
                    <p>#$r( "features.flow.body" )#</p>
                    <div class="metric-panel">
                        <div class="metric-row">
                            <div><small>#$r( "metric.cycle" )#</small><strong>#$r( "metric.days" )#</strong><em>↘ #$r( "metric.change" )#</em></div>
                            <div><small>#$r( "metric.throughput" )#</small><strong>#$r( "metric.cards" )#</strong><span>#$r( "metric.week" )#</span></div>
                        </div>
                        <div class="flow-chart" aria-hidden="true"><i></i><i></i><i></i><i></i></div>
                    </div>
                </article>

                <article class="feature-card feature-automation">
                    <div class="feature-icon icon-bolt"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg></div>
                    <h3>#$r( "features.automation.title" )#</h3>
                    <p>#$r( "features.automation.body" )#</p>
                    <div class="automation-panel">
                        <div><small>#$r( "automation.when" )#</small><strong><i class="mini-dot amber"></i> #$r( "automation.whenValue" )#</strong></div>
                        <span class="connector-line"></span>
                        <div><small>#$r( "automation.then" )#</small><strong><i class="mini-dot purple"></i> #$r( "automation.thenValue" )#</strong></div>
                    </div>
                </article>

                <article class="feature-card feature-connect">
                    <div class="feature-icon icon-link"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##link"></use></svg></div>
                    <h3>#$r( "features.embed.title" )#</h3>
                    <p>#$r( "features.embed.body" )#</p>
                    <div class="orbit-panel" aria-hidden="true">
                        <span class="orbit-center"><i></i><i></i><i></i></span>
                        <span class="orbit orbit-one"></span>
                        <span class="orbit orbit-two"></span>
                        <b class="satellite sat-one">V</b>
                        <b class="satellite sat-two">F</b>
                        <b class="satellite sat-three"><svg class="icon"><use href="/resources/icons.svg##external"></use></svg></b>
                    </div>
                </article>

                <article class="feature-card feature-policy">
                    <div class="feature-icon icon-limit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##columns"></use></svg></div>
                    <h3>#$r( "features.policy.title" )#</h3>
                    <p>#$r( "features.policy.body" )#</p>
                    <div class="wip-panel">
                        <div class="wip-top"><strong>#$r( "features.policy.lane" )#</strong><span>2 / 3</span></div>
                        <div class="wip-progress"><i></i></div>
                        <div class="mini-cards"><span></span><span></span><span class="empty"></span></div>
                    </div>
                </article>
            </div>
        </div>
    </section>

    <section class="embed-section section">
        <div class="shell embed-layout">
            <div class="embed-copy">
                <p class="eyebrow eyebrow-light"><span></span>#$r( "embed.badge" )#</p>
                <h2>#$r( "embed.title" )#</h2>
                <p>#$r( "embed.body" )#</p>
                <div class="chip-list">
                    <span>#$r( "embed.api" )#</span>
                    <span>#$r( "embed.webhooks" )#</span>
                    <span>#$r( "embed.sso" )#</span>
                    <span>#$r( "embed.theme" )#</span>
                </div>
            </div>
            <div class="embed-visual" aria-hidden="true">
                <div class="product-node node-voice"><b>TV</b><span>TaborVoice</span></div>
                <div class="product-node node-flow"><b>TF</b><span>TaborFlow</span></div>
                <div class="product-node node-custom"><b><svg class="icon"><use href="/resources/icons.svg##plus"></use></svg></b><span>Your product</span></div>
                <div class="lane-core">
                    <span class="brand-mark"><i></i><i></i><i></i></span>
                    <strong>TaborLane</strong>
                    <small>Workflow core</small>
                </div>
                <i class="route route-a"></i>
                <i class="route route-b"></i>
                <i class="route route-c"></i>
            </div>
        </div>
    </section>

    <section class="pricing-section section" id="pricing">
        <div class="shell">
            <div class="pricing-heading">
                <p class="eyebrow"><span></span>#$r( "pricing.eyebrow" )#</p>
                <h2>#$r( "pricing.title" )#</h2>
                <p>#$r( "pricing.body" )#</p>
                <div class="billing-toggle" data-billing-toggle>
                    <button type="button" class="active" data-billing="monthly">#$r( "pricing.monthly" )#</button>
                    <button type="button" data-billing="yearly">#$r( "pricing.yearly" )# <span>#$r( "pricing.save" )#</span></button>
                </div>
            </div>

            <div class="pricing-grid">
                <article class="price-card">
                    <h3>#$r( "pricing.free.name" )#</h3>
                    <p class="price-description">#$r( "pricing.free.body" )#</p>
                    <div class="price"><strong>#$r( "pricing.free.price" )#</strong><span>#$r( "pricing.free.period" )#</span></div>
                    <a class="button button-outline" href="/signup">#$r( "pricing.free.cta" )#</a>
                    <ul>
                        <li>#$r( "pricing.free.f1" )#</li>
                        <li>#$r( "pricing.free.f2" )#</li>
                        <li>#$r( "pricing.free.f3" )#</li>
                        <li>#$r( "pricing.free.f4" )#</li>
                        <li>#$r( "pricing.free.f5" )#</li>
                    </ul>
                </article>

                <article class="price-card premium-card">
                    <span class="popular-badge">#$r( "pricing.premium.badge" )#</span>
                    <h3>#$r( "pricing.premium.name" )#</h3>
                    <p class="price-description">#$r( "pricing.premium.body" )#</p>
                    <div class="price">
                        <strong data-monthly="#encodeForHTMLAttribute( $r( 'pricing.premium.priceMonthly' ) )#" data-yearly="#encodeForHTMLAttribute( $r( 'pricing.premium.priceYearly' ) )#">#$r( "pricing.premium.priceMonthly" )#</strong>
                        <span>#$r( "pricing.premium.period" )#</span>
                    </div>
                    <a class="button button-primary" href="/signup">#$r( "pricing.premium.cta" )# <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg></a>
                    <ul>
                        <li>#$r( "pricing.premium.f1" )#</li>
                        <li>#$r( "pricing.premium.f2" )#</li>
                        <li>#$r( "pricing.premium.f3" )#</li>
                        <li>#$r( "pricing.premium.f4" )#</li>
                        <li>#$r( "pricing.premium.f5" )#</li>
                        <li>#$r( "pricing.premium.f6" )#</li>
                    </ul>
                </article>
            </div>
        </div>
    </section>

    <section class="final-cta section">
        <div class="shell cta-card">
            <div>
                <p class="eyebrow eyebrow-light"><span></span>#$r( "cta.eyebrow" )#</p>
                <h2>#$r( "cta.title" )#</h2>
                <p>#$r( "cta.body" )#</p>
            </div>
            <div class="cta-actions">
                <a class="button button-white" href="/signup">#$r( "cta.primary" )# <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg></a>
                <a class="button button-clear" href="/login">#$r( "cta.secondary" )#</a>
            </div>
        </div>
    </section>
</main>

<footer class="site-footer">
    <div class="shell footer-grid">
        <div>
            <a class="brand footer-brand" href="/">
                <span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span>
                <span class="brand-name">Tabor<span>Lane</span></span>
            </a>
            <p>#$r( "footer.body" )#</p>
        </div>
        <div><strong>#$r( "footer.product" )#</strong><a href="##solutions">#$r( "footer.features" )#</a><a href="##pricing">#$r( "footer.pricing" )#</a><a href="/app">#$r( "footer.workspace" )#</a></div>
        <div><strong>#$r( "footer.company" )#</strong><a href="##">#$r( "footer.about" )#</a><a href="##">#$r( "footer.privacy" )#</a><a href="##">#$r( "footer.terms" )#</a></div>
    </div>
    <div class="shell footer-bottom"><span>© #year( now() )# #$r( "footer.rights" )#</span><span>EN · PT-BR</span></div>
</footer>
</cfoutput>
