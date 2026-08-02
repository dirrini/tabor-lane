<cfscript>
	analytics = prc.analytics ?: {};
	analyticsSummary = analytics.summary ?: {};
	analyticsPeriod = analytics.period ?: {};
	analyticsTimezone = analyticsPeriod.timezone ?: "UTC";
	throughputTrend = analytics.throughputTrend ?: [];
	cardsByLane = analytics.cardsByLane ?: [];
	agingCards = analytics.agingCards ?: [];
	priorityDistribution = analytics.priorityDistribution ?: [];
	assigneeDistribution = analytics.assigneeDistribution ?: [];
	dataQuality = analytics.dataQuality ?: {};
	analyticsAppliedFilters = analytics.filters ?: {};
	analyticsError = lCase( prc.analyticsError ?: "" );
	if ( !analyticsError.len() && ( !( analytics.found ?: false ) || lCase( analytics.code ?: "ok" ) != "ok" ) ) {
		analyticsError = lCase( analytics.code ?: "generic" );
	}
	allowedErrorCodes = "invalid_filter,invalid_period,not_found,forbidden,generic";
	if ( analyticsError.len() && !listFindNoCase( allowedErrorCodes, analyticsError ) ) analyticsError = "generic";
	analyticsReady = !analyticsError.len()
		&& ( analytics.found ?: false )
		&& lCase( analytics.code ?: "ok" ) == "ok";
	if ( !analyticsReady && !analyticsError.len() ) analyticsError = "generic";
	locale = getFWLocale();

	durationLabel = function( required numeric seconds ){
		var durationSeconds = max( 0, val( arguments.seconds ) );
		if ( durationSeconds < 60 ) return $r( "analytics.duration.lessThanMinute" );
		if ( durationSeconds < 3600 ) {
			return ceiling( durationSeconds / 60 ) & " " & $r( "analytics.duration.minuteShort" );
		}
		if ( durationSeconds < 86400 ) {
			return round( durationSeconds / 3600 ) & " " & $r( "analytics.duration.hourShort" );
		}
		return round( durationSeconds / 86400 ) & " " & $r( "analytics.duration.dayShort" );
	};

	dateLabel = function( required string value, boolean includeYear=false ){
		if ( !isValid( "date", arguments.value ) ) return arguments.value;
		var mask = arguments.includeYear
			? ( locale == "pt_BR" ? "dd/MM/yyyy" : "MMM d, yyyy" )
			: ( locale == "pt_BR" ? "dd/MM" : "MMM d" );
		return dateFormat( parseDateTime( arguments.value ), mask );
	};

	cardUnit = function( required numeric count ){
		return val( arguments.count ) == 1
			? $r( "analytics.unit.card" )
			: $r( "analytics.unit.cards" );
	};

	throughputTotal = 0;
	throughputMaximum = 1;
	for ( throughputItem in throughputTrend ) {
		throughputCount = val( throughputItem.count ?: 0 );
		throughputTotal += throughputCount;
		throughputMaximum = max( throughputMaximum, throughputCount );
	}

	chartWidth = 760;
	chartHeight = 240;
	chartLeft = 42;
	chartRight = 18;
	chartTop = 18;
	chartBottom = 34;
	chartPlotWidth = chartWidth - chartLeft - chartRight;
	chartPlotHeight = chartHeight - chartTop - chartBottom;
	chartBaseline = chartTop + chartPlotHeight;
	throughputPoints = [];
	throughputPolyline = "";
	for ( throughputIndex=1; throughputIndex<=throughputTrend.len(); throughputIndex++ ) {
		throughputPoint = throughputTrend[ throughputIndex ];
		pointX = throughputTrend.len() == 1
			? round( chartLeft + chartPlotWidth / 2 )
			: round( chartLeft + ( throughputIndex - 1 ) * chartPlotWidth / ( throughputTrend.len() - 1 ) );
		pointY = round( chartTop + chartPlotHeight - ( val( throughputPoint.count ?: 0 ) / throughputMaximum ) * chartPlotHeight );
		throughputPoints.append( {
			x=pointX,
			y=pointY,
			date=throughputPoint.date ?: "",
			count=val( throughputPoint.count ?: 0 )
		} );
		throughputPolyline &= ( throughputPolyline.len() ? " " : "" ) & pointX & "," & pointY;
	}
	chartTicks = [];
	chartTickDivisions = min( 4, throughputMaximum );
	for ( chartTickIndex=0; chartTickIndex<=chartTickDivisions; chartTickIndex++ ) {
		chartTickValue = round(
			throughputMaximum * ( chartTickDivisions - chartTickIndex ) / chartTickDivisions
		);
		chartTicks.append( {
			value = chartTickValue,
			y = round( chartTop + chartTickIndex * chartPlotHeight / chartTickDivisions )
		} );
	}

	analyticsCardReturnQuery = "returnTo=analytics"
		& "&returnFromDate=" & urlEncodedFormat( analyticsPeriod.from ?: "" )
		& "&returnToDate=" & urlEncodedFormat( analyticsPeriod.to ?: "" );
	if ( ( analyticsAppliedFilters.boardId ?: "" ).len() ) {
		analyticsCardReturnQuery &= "&returnBoardId="
			& urlEncodedFormat( analyticsAppliedFilters.boardId );
	}
	if ( ( analyticsAppliedFilters.assigneeId ?: "" ).len() ) {
		analyticsCardReturnQuery &= "&returnAssigneeId="
			& urlEncodedFormat( analyticsAppliedFilters.assigneeId );
	}

	laneMaximum = 1;
	for ( laneItem in cardsByLane ) laneMaximum = max( laneMaximum, val( laneItem.cardCount ?: 0 ) );
	priorityMaximum = 1;
	for ( priorityItem in priorityDistribution ) priorityMaximum = max( priorityMaximum, val( priorityItem.count ?: 0 ) );
	assigneeMaximum = 1;
	for ( assigneeItem in assigneeDistribution ) assigneeMaximum = max( assigneeMaximum, val( assigneeItem.count ?: 0 ) );

	qualityMetrics = [
		{ key="completedSamples",label="analytics.dataQuality.completedSamples" },
		{ key="leadSamples",label="analytics.dataQuality.leadSamples" },
		{ key="cycleSamples",label="analytics.dataQuality.cycleSamples" },
		{ key="missingStartedAt",label="analytics.dataQuality.missingStartedAt" },
		{ key="invalidLeadTime",label="analytics.dataQuality.invalidLeadTime" },
		{ key="invalidCycleTime",label="analytics.dataQuality.invalidCycleTime" }
	];
	knownWarnings = "completion_uses_designated_lane,cycle_time_starts_on_first_lane_change,historical_throughput_uses_latest_completion,completed_cards_missing_started_at,assignee_filter_uses_current_assignment";
</cfscript>
<cfoutput>
<section id="analytics-results" class="analytics-results" aria-live="polite" aria-busy="false">
	<cfif !analyticsReady>
		<div class="analytics-error-state" role="alert">
			<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg></span>
			<p>#$r( "analytics.error.#analyticsError#" )#</p>
		</div>
	<cfelse>
		<section class="analytics-dashboard-section analytics-current-section" aria-labelledby="analytics-current-title">
			<header class="analytics-section-heading">
				<div>
					<small>#$r( "analytics.eyebrow" )#</small>
					<h2 id="analytics-current-title">#$r( "analytics.current.title" )#</h2>
					<p>#$r( "analytics.current.body" )#</p>
				</div>
				<span class="analytics-period-chip"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg> #encodeForHTML( analyticsTimezone )#</span>
			</header>

			<div class="analytics-kpis">
				<article class="analytics-kpi-card">
					<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##list-checks"></use></svg></span>
					<div><strong>#val( analyticsSummary.openCards ?: 0 )#</strong><small>#$r( "analytics.metric.openCards" )#</small></div>
				</article>
				<article class="analytics-kpi-card">
					<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##columns"></use></svg></span>
					<div><strong>#val( analyticsSummary.currentWip ?: 0 )#</strong><small>#$r( "analytics.metric.currentWip" )#</small></div>
				</article>
				<article class="analytics-kpi-card #( val( analyticsSummary.overdue ?: 0 ) ? 'attention' : '' )#">
					<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg></span>
					<div><strong>#val( analyticsSummary.overdue ?: 0 )#</strong><small>#$r( "analytics.metric.overdue" )#</small></div>
				</article>
				<article class="analytics-kpi-card">
					<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg></span>
					<div><strong>#val( analyticsSummary.dueNext7Days ?: 0 )#</strong><small>#$r( "analytics.metric.dueNext7Days" )#</small></div>
				</article>
			</div>
		</section>

		<section class="analytics-dashboard-section analytics-period-section" aria-labelledby="analytics-period-title">
			<header class="analytics-section-heading">
				<div>
					<small>#$r( "analytics.filter.from" )# &ndash; #$r( "analytics.filter.to" )#</small>
					<h2 id="analytics-period-title">#$r( "analytics.period.title" )#</h2>
					<p>#$r( "analytics.period.body" )#</p>
				</div>
				<span class="analytics-period-chip">
					<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg>
					#encodeForHTML( dateLabel( analyticsPeriod.from ?: "", true ) )# &ndash; #encodeForHTML( dateLabel( analyticsPeriod.to ?: "", true ) )#
				</span>
			</header>

			<div class="analytics-period-grid">
				<article class="analytics-panel analytics-throughput-panel">
					<div class="analytics-panel-heading">
						<div>
							<h3>#$r( "analytics.metric.throughput" )#</h3>
							<p>#$r( "analytics.throughput.body" )#</p>
						</div>
						<strong>#val( analyticsSummary.throughput ?: 0 )# <small>#encodeForHTML( cardUnit( analyticsSummary.throughput ?: 0 ) )#</small></strong>
					</div>
					<cfif !throughputTotal>
						<div class="analytics-panel-empty">
							<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chart"></use></svg>
							<h4>#$r( "analytics.empty.throughput.title" )#</h4>
							<p>#$r( "analytics.empty.throughput.body" )#</p>
						</div>
					<cfelse>
						<div class="analytics-line-chart">
							<svg viewBox="0 0 #chartWidth# #chartHeight#" role="img" aria-labelledby="throughput-chart-title throughput-chart-description">
								<title id="throughput-chart-title">#$r( "analytics.throughput.title" )#</title>
								<desc id="throughput-chart-description">#$r( "analytics.throughput.body" )#</desc>
								<defs>
									<linearGradient id="throughput-area" x1="0" y1="0" x2="0" y2="1">
										<stop offset="0%" stop-color="##c63d4b" stop-opacity=".22"></stop>
										<stop offset="100%" stop-color="##c63d4b" stop-opacity="0"></stop>
									</linearGradient>
								</defs>
								<cfloop array="#chartTicks#" item="chartTick">
									<line class="chart-grid-line" x1="#chartLeft#" y1="#chartTick.y#" x2="#chartWidth-chartRight#" y2="#chartTick.y#"></line>
									<text class="chart-axis-label" x="#chartLeft-8#" y="#chartTick.y+3#" text-anchor="end">#chartTick.value#</text>
								</cfloop>
								<path class="chart-area" d="M #chartLeft# #chartBaseline# L #throughputPolyline# L #chartWidth-chartRight# #chartBaseline# Z"></path>
								<polyline class="chart-line" points="#throughputPolyline#"></polyline>
								<cfif throughputPoints.len() lte 62>
									<cfloop array="#throughputPoints#" item="chartPoint">
										<circle class="chart-point" cx="#chartPoint.x#" cy="#chartPoint.y#" r="4">
											<title>#encodeForHTML( dateLabel( chartPoint.date, true ) )#: #chartPoint.count# #encodeForHTML( cardUnit( chartPoint.count ) )#</title>
										</circle>
									</cfloop>
								</cfif>
							</svg>
							<div class="analytics-chart-dates" aria-hidden="true">
								<span>#encodeForHTML( dateLabel( throughputTrend[ 1 ].date ?: "", true ) )#</span>
								<cfif throughputTrend.len() gt 2><span>#encodeForHTML( dateLabel( throughputTrend[ ceiling( throughputTrend.len() / 2 ) ].date ?: "", true ) )#</span></cfif>
								<cfif throughputTrend.len() gt 1><span>#encodeForHTML( dateLabel( throughputTrend[ throughputTrend.len() ].date ?: "", true ) )#</span></cfif>
							</div>
							<ul class="sr-only">
								<cfloop array="#throughputTrend#" item="accessiblePoint">
									<li>#encodeForHTML( dateLabel( accessiblePoint.date ?: "", true ) )#: #val( accessiblePoint.count ?: 0 )# #encodeForHTML( cardUnit( accessiblePoint.count ?: 0 ) )#</li>
								</cfloop>
							</ul>
						</div>
					</cfif>
				</article>

				<div class="analytics-time-panels">
					<cfloop array="#[
						{ key='leadTime',label='analytics.metric.leadTime',icon='clock' },
						{ key='cycleTime',label='analytics.metric.cycleTime',icon='columns' }
					]#" item="timeMetric">
						<cfset timeData=analyticsSummary[ timeMetric.key ] ?: {}>
						<article class="analytics-panel analytics-time-card">
							<div class="analytics-time-card-title">
								<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg###timeMetric.icon#"></use></svg></span>
								<h3>#$r( timeMetric.label )#</h3>
							</div>
							<cfif !val( timeData.sampleSize ?: 0 )>
								<p class="analytics-no-samples">#$r( "analytics.stat.noSamples" )#</p>
							<cfelse>
								<strong class="analytics-time-primary">#encodeForHTML( durationLabel( timeData.medianSeconds ?: 0 ) )# <small>#$r( "analytics.stat.median" )#</small></strong>
								<dl class="analytics-time-stats">
									<div><dt>#$r( "analytics.stat.average" )#</dt><dd>#encodeForHTML( durationLabel( timeData.averageSeconds ?: 0 ) )#</dd></div>
									<div><dt>#$r( "analytics.stat.p85" )#</dt><dd>#encodeForHTML( durationLabel( timeData.p85Seconds ?: 0 ) )#</dd></div>
									<div><dt>#$r( "analytics.stat.samples" )#</dt><dd>#val( timeData.sampleSize ?: 0 )#</dd></div>
								</dl>
							</cfif>
						</article>
					</cfloop>
				</div>
			</div>
		</section>

		<section class="analytics-dashboard-section" aria-labelledby="analytics-flow-title">
			<header class="analytics-section-heading">
				<div>
					<small>#$r( "analytics.eyebrow" )#</small>
					<h2 id="analytics-flow-title">#$r( "analytics.lanes.title" )#</h2>
					<p>#$r( "analytics.lanes.body" )#</p>
				</div>
			</header>

			<div class="analytics-distribution-grid">
				<article class="analytics-panel analytics-lanes-panel">
					<div class="analytics-panel-heading">
						<div><h3>#$r( "analytics.lanes.title" )#</h3><p>#$r( "analytics.lanes.body" )#</p></div>
					</div>
					<cfif !cardsByLane.len() || !val( analyticsSummary.openCards ?: 0 )>
						<div class="analytics-panel-empty compact">
							<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##columns"></use></svg>
							<h4>#$r( "analytics.empty.current.title" )#</h4>
							<p>#$r( "analytics.empty.current.body" )#</p>
						</div>
					<cfelse>
						<div class="analytics-bar-list">
							<cfloop array="#cardsByLane#" item="lanePoint">
								<cfset lanePercent=round( val( lanePoint.cardCount ?: 0 ) * 1000 / laneMaximum ) / 10>
								<div class="analytics-bar-row">
									<div>
										<span><i class="column-dot dot-#encodeForHTMLAttribute( lanePoint.color ?: 'slate' )#"></i><strong>#encodeForHTML( lanePoint.laneName ?: "" )#</strong><small>#encodeForHTML( lanePoint.boardName ?: "" )#</small></span>
										<b>#val( lanePoint.cardCount ?: 0 )#</b>
									</div>
									<span class="analytics-bar-track"><i style="--analytics-bar:#lanePercent#%"></i></span>
								</div>
							</cfloop>
						</div>
					</cfif>
				</article>

				<article class="analytics-panel">
					<div class="analytics-panel-heading">
						<div><h3>#$r( "analytics.priority.title" )#</h3><p>#$r( "analytics.priority.body" )#</p></div>
					</div>
					<cfif !val( analyticsSummary.openCards ?: 0 )>
						<div class="analytics-panel-empty compact">
							<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chart"></use></svg>
							<h4>#$r( "analytics.empty.distribution.title" )#</h4>
							<p>#$r( "analytics.empty.distribution.body" )#</p>
						</div>
					<cfelse>
						<div class="analytics-bar-list">
							<cfloop array="#priorityDistribution#" item="priorityPoint">
								<cfset priorityPercent=round( val( priorityPoint.count ?: 0 ) * 1000 / priorityMaximum ) / 10>
								<div class="analytics-bar-row priority-row-#encodeForHTMLAttribute( priorityPoint.priority ?: 'none' )#">
									<div><span><strong>#encodeForHTML( $r( "card.priority.#priorityPoint.priority#" ) )#</strong></span><b>#val( priorityPoint.count ?: 0 )#</b></div>
									<span class="analytics-bar-track"><i style="--analytics-bar:#priorityPercent#%"></i></span>
								</div>
							</cfloop>
						</div>
					</cfif>
				</article>

				<article class="analytics-panel">
					<div class="analytics-panel-heading">
						<div><h3>#$r( "analytics.assignee.title" )#</h3><p>#$r( "analytics.assignee.body" )#</p></div>
					</div>
					<cfif !assigneeDistribution.len() || !val( analyticsSummary.openCards ?: 0 )>
						<div class="analytics-panel-empty compact">
							<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##users"></use></svg>
							<h4>#$r( "analytics.empty.distribution.title" )#</h4>
							<p>#$r( "analytics.empty.distribution.body" )#</p>
						</div>
					<cfelse>
						<div class="analytics-bar-list">
							<cfloop array="#assigneeDistribution#" item="assigneePoint">
								<cfset assigneePercent=round( val( assigneePoint.count ?: 0 ) * 1000 / assigneeMaximum ) / 10>
								<div class="analytics-bar-row">
									<div><span><strong>#encodeForHTML( ( assigneePoint.unassigned ?: false ) ? $r( "card.unassigned" ) : ( assigneePoint.assigneeName ?: "" ) )#</strong></span><b>#val( assigneePoint.count ?: 0 )#</b></div>
									<span class="analytics-bar-track"><i style="--analytics-bar:#assigneePercent#%"></i></span>
								</div>
							</cfloop>
						</div>
					</cfif>
				</article>
			</div>
		</section>

		<section class="analytics-dashboard-section" aria-labelledby="analytics-aging-title">
			<header class="analytics-section-heading">
				<div>
					<small>#$r( "analytics.eyebrow" )#</small>
					<h2 id="analytics-aging-title">#$r( "analytics.aging.title" )#</h2>
					<p>#$r( "analytics.aging.body" )#</p>
				</div>
			</header>
			<article class="analytics-panel analytics-aging-panel">
				<cfif !agingCards.len()>
					<div class="analytics-panel-empty">
						<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg>
						<h4>#$r( "analytics.empty.aging.title" )#</h4>
						<p>#$r( "analytics.empty.aging.body" )#</p>
					</div>
				<cfelse>
					<div class="analytics-aging-list">
						<cfloop array="#agingCards#" item="agingCard" index="agingIndex">
							<article>
								<b class="analytics-aging-rank">#agingIndex#</b>
								<div class="analytics-aging-card-copy">
									<h3>#encodeForHTML( agingCard.title ?: "" )#</h3>
									<p><span class="column-dot dot-#encodeForHTMLAttribute( agingCard.laneColor ?: 'slate' )#"></span>#encodeForHTML( agingCard.boardName ?: "" )# <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg> #encodeForHTML( agingCard.laneName ?: "" )#</p>
								</div>
								<dl>
									<div><dt>#$r( "analytics.aging.cardAge" )#</dt><dd>#encodeForHTML( durationLabel( agingCard.cardAgeSeconds ?: 0 ) )#</dd></div>
									<div><dt>#$r( "analytics.aging.wipAge" )#</dt><dd>#( agingCard.hasStarted ?: false ) ? encodeForHTML( durationLabel( agingCard.wipAgeSeconds ?: 0 ) ) : $r( "analytics.aging.notStarted" )#</dd></div>
									<div><dt>#$r( "analytics.aging.laneAge" )#</dt><dd>#encodeForHTML( durationLabel( agingCard.laneAgeSeconds ?: 0 ) )#</dd></div>
								</dl>
								<a class="button button-ghost button-small" href="/app/cards/#encodeForURL( agingCard.cardId ?: '' )#?#analyticsCardReturnQuery#"
									hx-get="/app/cards/#encodeForURL( agingCard.cardId ?: '' )#?#analyticsCardReturnQuery#"
									hx-target="##workspace-main"
									hx-select="##workspace-main"
									hx-swap="outerHTML show:top"
									hx-push-url="true">
									#$r( "analytics.aging.openCard" )#
									<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg>
								</a>
							</article>
						</cfloop>
					</div>
				</cfif>
			</article>
		</section>

		<details class="analytics-panel analytics-data-quality">
			<summary>
				<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##info"></use></svg></span>
				<div><h2>#$r( "analytics.dataQuality.title" )#</h2><p>#$r( "analytics.dataQuality.body" )#</p></div>
				<b>#$r( "analytics.dataQuality.coverage" )#: #val( dataQuality.cycleCoveragePercent ?: 0 )#%</b>
				<svg class="icon analytics-details-chevron" aria-hidden="true"><use href="/resources/icons.svg##chevron-down"></use></svg>
			</summary>
			<div class="analytics-data-quality-body">
				<div class="analytics-quality-metrics">
					<cfloop array="#qualityMetrics#" item="qualityMetric">
						<div><strong>#val( dataQuality[ qualityMetric.key ] ?: 0 )#</strong><small>#$r( qualityMetric.label )#</small></div>
					</cfloop>
				</div>
				<p class="analytics-semantics">
					<strong>#$r( "analytics.dataQuality.semantics" )#:</strong>
					<cfif ( dataQuality.semanticsVersion ?: "" ) == "legacy-v1">
						#$r( "analytics.dataQuality.semantics.legacy-v1" )#
					<cfelse>
						#encodeForHTML( dataQuality.semanticsVersion ?: "" )#
					</cfif>
				</p>
				<cfif ( dataQuality.warnings ?: [] ).len()>
					<ul class="analytics-warning-list">
						<cfloop array="#dataQuality.warnings#" item="qualityWarning">
							<li>
								<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg>
								<cfif listFindNoCase( knownWarnings, qualityWarning )>
									#$r( "analytics.dataQuality.warning.#qualityWarning#" )#
								<cfelse>
									#encodeForHTML( qualityWarning )#
								</cfif>
							</li>
						</cfloop>
					</ul>
				</cfif>
			</div>
		</details>
	</cfif>
</section>
</cfoutput>
