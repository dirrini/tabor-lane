<cfscript>
    card = prc.cardDetails.card;
    locale = getFWLocale();
    dateMask = locale == "pt_BR" ? "dd/MM/yyyy 'às' HH:mm" : "MMM d, yyyy 'at' h:mm tt";
    labelsValue = card.labels_csv ?: "";
    knownErrors = "expired,invalid,read_only,invalid_assignee,invalid_comment,attachment_storage";
    errorMessage = listFindNoCase( knownErrors, prc.error )
        ? $r( "card.error.#prc.error#" )
        : $r( "card.error" );
    workspacePage = "app";
    backUrl = "/app?boardId=" & encodeForURL( card.board_id );
    backKey = "card.back";
    returnToValue = "";
    if ( prc.returnTo == "my-work" ) {
        workspacePage = "myWork";
        backUrl = "/app/my-work";
        backKey = "card.backMyWork";
        returnToValue = "my-work";
    } else if ( prc.returnTo == "analytics" ) {
        workspacePage = "analytics";
        backUrl = prc.analyticsReturnUrl;
        backKey = "card.backAnalytics";
        returnToValue = "analytics";
    } else if ( prc.returnTo == "notifications" ) {
        workspacePage = "notifications";
        backUrl = "/app/notifications";
        backKey = "card.backNotifications";
        returnToValue = "notifications";
    }
    analyticsReturnFilters = prc.analyticsReturnFilters ?: {
        fromDate = "",
        toDate = "",
        boardId = "",
        assigneeId = ""
    };
</cfscript>
<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
<section id="workspace-main" class="workspace-main card-details-main" data-workspace-page="#workspacePage#" data-card-csrf-token="#encodeForHTMLAttribute( prc.cardCsrfToken )#">
    <a class="card-back-link" href="#backUrl#" hx-get="#backUrl#" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true">
        <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg>
        #$r( backKey )#
    </a>

    <header class="card-details-header">
        <div>
            <small>#encodeForHTML( card.board_name )# · #encodeForHTML( card.column_name )#</small>
            <h1>#encodeForHTML( card.title )#</h1>
        </div>
        <span class="priority-chip priority-#encodeForHTMLAttribute( card.priority )#">#$r( "card.priority.#card.priority#" )#</span>
    </header>

    <cfif prc.notice.len()><div class="form-success">#$r( "card.#prc.notice#" )#</div></cfif>
    <cfif prc.error.len()><div class="form-errors"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg><p>#errorMessage#</p></div></cfif>
    <cfif !prc.canEditCard><div class="billing-notice">#$r( "card.readOnly" )#</div></cfif>

    <div class="card-details-layout">
        <div class="card-details-primary">
            <section class="card-panel">
                <div class="panel-heading"><div><h2>#$r( "card.details" )#</h2></div></div>
                <form class="card-form" method="post" action="/app/cards/#encodeForURL( card.id )#">
                    <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.cardCsrfToken )#">
                    <input type="hidden" name="returnTo" value="#returnToValue#">
                    <cfif returnToValue == "analytics">
                        <input type="hidden" name="returnFromDate" value="#encodeForHTMLAttribute( analyticsReturnFilters.fromDate )#">
                        <input type="hidden" name="returnToDate" value="#encodeForHTMLAttribute( analyticsReturnFilters.toDate )#">
                        <input type="hidden" name="returnBoardId" value="#encodeForHTMLAttribute( analyticsReturnFilters.boardId )#">
                        <input type="hidden" name="returnAssigneeId" value="#encodeForHTMLAttribute( analyticsReturnFilters.assigneeId )#">
                    </cfif>
                    <label>#$r( "app.card.title" )#<input name="title" maxlength="255" required value="#encodeForHTMLAttribute( card.title )#" #prc.canEditCard ? "" : "disabled"#></label>
                    <label class="card-form-wide">#$r( "card.description" )#<textarea name="description" rows="7" maxlength="20000" #prc.canEditCard ? "" : "disabled"#>#encodeForHTML( card.description ?: "" )#</textarea></label>
                    <label>#$r( "card.priority" )#<select name="priority" #prc.canEditCard ? "" : "disabled"#><cfloop list="none,low,medium,high,urgent" item="priority"><option value="#priority#" #card.priority == priority ? "selected" : ""#>#$r( "card.priority.#priority#" )#</option></cfloop></select></label>
                    <label>#$r( "card.assignee" )#<select name="assigneeId" #prc.canEditCard ? "" : "disabled"#><option value="">#$r( "card.unassigned" )#</option><cfloop array="#prc.cardDetails.members#" item="member"><option value="#encodeForHTMLAttribute( member.id )#" #card.assignee_id == member.id ? "selected" : ""#>#encodeForHTML( member.display_name )#</option></cfloop></select></label>
                    <label>#$r( "card.dueDate" )#<input type="date" name="dueDate" value="#encodeForHTMLAttribute( card.due_date ?: "" )#" #prc.canEditCard ? "" : "disabled"#></label>
                    <label>#$r( "card.labels" )#<input name="labels" maxlength="410" value="#encodeForHTMLAttribute( labelsValue )#" #prc.canEditCard ? "" : "disabled"#><small>#$r( "card.labelsHint" )#</small></label>
                    <cfif prc.canEditCard><button class="button button-primary card-form-submit" type="submit">#$r( "card.save" )#</button></cfif>
                </form>
            </section>

            <section id="card-attachments" class="card-panel">
                <div class="panel-heading"><div><h2>#$r( "card.attachments" )#</h2><p>#$r( "card.attachment.hint" )#</p></div><span>#prc.attachments.len()#</span></div>
                <cfif prc.canEditCard>
                    <form class="card-attachment-form" data-attachment-form data-presign-url="/app/cards/#encodeForURL( card.id )#/attachments/presign" data-complete-url-template="/app/cards/#encodeForURL( card.id )#/attachments/{id}/complete" data-uploading="#encodeForHTMLAttribute( $r( 'card.attachment.uploading' ) )#" data-error-default="#encodeForHTMLAttribute( $r( 'card.attachment.error' ) )#" data-error-file-too-large="#encodeForHTMLAttribute( $r( 'card.attachment.error.file_too_large' ) )#" data-error-quota="#encodeForHTMLAttribute( $r( 'card.attachment.error.quota' ) )#" data-error-upload-failed="#encodeForHTMLAttribute( $r( 'card.attachment.error.upload_failed' ) )#">
                        <label><span>#$r( "card.attachment.select" )#</span><input type="file" name="attachment" required></label>
                        <button class="button button-primary button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##paperclip"></use></svg><span data-attachment-submit-label>#$r( "card.attachment.upload" )#</span></button>
                        <p role="status" aria-live="polite" data-attachment-status></p>
                    </form>
                </cfif>
                <div class="card-attachment-list">
                    <cfif !prc.attachments.len()><p class="card-empty-copy">#$r( "card.attachment.empty" )#</p></cfif>
                    <cfloop array="#prc.attachments#" item="attachment">
                        <article class="card-attachment">
                            <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##paperclip"></use></svg>
                            <div><strong>#encodeForHTML( attachment.original_filename )#</strong><small>#numberFormat( attachment.size_bytes / 1048576, "0.00" )# MB · #encodeForHTML( attachment.uploader_name )#</small></div>
                            <a href="/app/attachments/#encodeForURL( attachment.id )#/download" target="_blank" rel="noopener" title="#encodeForHTMLAttribute( $r( 'card.attachment.download' ) )#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##external"></use></svg><span class="sr-only">#$r( "card.attachment.download" )#</span></a>
                            <cfif prc.canEditCard><form method="post" action="/app/cards/#encodeForURL( card.id )#/attachments/#encodeForURL( attachment.id )#/remove" hx-post="/app/cards/#encodeForURL( card.id )#/attachments/#encodeForURL( attachment.id )#/remove" hx-target="##card-attachments" hx-select="##card-attachments" hx-swap="outerHTML" data-attachment-remove data-confirm="#encodeForHTMLAttribute( $r( 'card.attachment.removeConfirm' ) )#"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.cardCsrfToken )#"><button type="submit" title="#encodeForHTMLAttribute( $r( 'card.attachment.remove' ) )#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##close"></use></svg><span class="sr-only">#$r( "card.attachment.remove" )#</span></button></form></cfif>
                        </article>
                    </cfloop>
                </div>
            </section>

            <section class="card-panel">
                <div class="panel-heading"><div><h2>#$r( "card.comments" )#</h2></div><span>#prc.cardDetails.comments.len()#</span></div>
                <cfif prc.canEditCard>
                    <form class="card-comment-form" method="post" action="/app/cards/#encodeForURL( card.id )#/comments">
                        <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.cardCsrfToken )#">
                        <input type="hidden" name="returnTo" value="#returnToValue#">
                        <cfif returnToValue == "analytics">
                            <input type="hidden" name="returnFromDate" value="#encodeForHTMLAttribute( analyticsReturnFilters.fromDate )#">
                            <input type="hidden" name="returnToDate" value="#encodeForHTMLAttribute( analyticsReturnFilters.toDate )#">
                            <input type="hidden" name="returnBoardId" value="#encodeForHTMLAttribute( analyticsReturnFilters.boardId )#">
                            <input type="hidden" name="returnAssigneeId" value="#encodeForHTMLAttribute( analyticsReturnFilters.assigneeId )#">
                        </cfif>
                        <label>#$r( "card.comment" )#<textarea name="body" rows="3" maxlength="5000" required placeholder="#encodeForHTMLAttribute( $r( 'card.commentPlaceholder' ) )#"></textarea></label>
                        <button class="button button-primary button-small" type="submit">#$r( "card.commentSubmit" )#</button>
                    </form>
                </cfif>
                <div class="card-comment-list">
                    <cfif !prc.cardDetails.comments.len()><p class="card-empty-copy">#$r( "card.noComments" )#</p></cfif>
                    <cfloop array="#prc.cardDetails.comments#" item="comment">
                        <article class="card-comment"><span class="user-avatar account-avatar"><span>#encodeForHTML( comment.author_initials )#</span><cfif len( comment.author_avatar_id ?: "" )><img src="/app/users/#encodeForURL( comment.author_id )#/avatar?v=#encodeForURL( comment.author_avatar_id )#" alt=""></cfif></span><div><strong>#encodeForHTML( comment.author_name )#</strong><time>#encodeForHTML( dateTimeFormat( comment.created_at, dateMask ) )#</time><p>#encodeForHTML( comment.body )#</p></div></article>
                    </cfloop>
                </div>
            </section>
        </div>

        <aside class="card-details-aside">
            <section class="card-panel">
                <div class="panel-heading"><div><h2>#$r( "card.activity" )#</h2></div></div>
                <div class="card-activity-list">
                    <cfloop array="#prc.cardDetails.activity#" item="activity"><article><span></span><p><strong>#encodeForHTML( activity.actor_name )#</strong> #$r( "card.activity.#activity.action#" )#<time>#encodeForHTML( dateTimeFormat( activity.created_at, dateMask ) )#</time></p></article></cfloop>
                </div>
            </section>
            <section class="card-panel card-metadata">
                <dl><div><dt>#$r( "card.createdAt" )#</dt><dd>#encodeForHTML( dateTimeFormat( card.created_at, dateMask ) )#</dd></div><div><dt>#$r( "card.updatedAt" )#</dt><dd>#encodeForHTML( dateTimeFormat( card.updated_at, dateMask ) )#</dd></div></dl>
                <cfif prc.canEditCard>
                    <form method="post" action="/app/cards/#encodeForURL( card.id )#/archive" data-card-archive data-confirm="#encodeForHTMLAttribute( $r( 'card.archiveConfirm' ) )#">
                        <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.cardCsrfToken )#">
                        <input type="hidden" name="returnTo" value="#returnToValue#">
                        <cfif returnToValue == "analytics">
                            <input type="hidden" name="returnFromDate" value="#encodeForHTMLAttribute( analyticsReturnFilters.fromDate )#">
                            <input type="hidden" name="returnToDate" value="#encodeForHTMLAttribute( analyticsReturnFilters.toDate )#">
                            <input type="hidden" name="returnBoardId" value="#encodeForHTMLAttribute( analyticsReturnFilters.boardId )#">
                            <input type="hidden" name="returnAssigneeId" value="#encodeForHTMLAttribute( analyticsReturnFilters.assigneeId )#">
                        </cfif>
                        <button class="button button-ghost" type="submit">#$r( "card.archive" )#</button>
                    </form>
                </cfif>
            </section>
        </aside>
    </div>
</section>
</cfoutput>
