from fastapi import APIRouter, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

from lexiquest_ai.auth import extract_bearer_token
from lexiquest_ai.content_reports import ContentReportError, closed_json


def content_report_router(*, settings, token_verifier, service):
    router = APIRouter()

    async def call(authorization, operation, *, moderation=False):
        user = await run_in_threadpool(token_verifier.verify, extract_bearer_token(authorization))
        if not settings.content_reports_enabled:
            raise HTTPException(503, detail={'code': 'REPORTS_DISABLED', 'message': 'Report transport is disabled.'})
        if user.is_anonymous is not False:
            raise HTTPException(403, detail={'code': 'REPORTS_ACCOUNT_REQUIRED', 'message': 'A registered account is required.'})
        if service is None:
            raise HTTPException(503, detail={'code': 'REPORTS_UNAVAILABLE', 'message': 'Report transport is unavailable.'})
        try:
            if moderation:
                await run_in_threadpool(service.require_moderator, user.uid)
            value = await operation(service, user.uid)
            if moderation:
                await run_in_threadpool(service.require_moderator, user.uid)
            return JSONResponse(content=value, headers={'Cache-Control': 'no-store'})
        except ContentReportError as error:
            codes = {'invalid_request': 400, 'digest_mismatch': 400, 'not_found': 404,
                     'moderator_required': 403, 'conflict': 409, 'deletion_pending': 409,
                     'rate_limited': 429, 'unavailable': 503}
            code = error.code if error.code in codes else 'unavailable'
            raise HTTPException(codes[code], detail={'code': 'REPORTS_' + code.upper(),
                'message': 'The report operation could not be completed.'},
                headers={'Retry-After': '60'} if code == 'rate_limited' else None) from None
        except Exception:
            raise HTTPException(503, detail={'code': 'REPORTS_UNAVAILABLE',
                                            'message': 'Report transport is unavailable.'}) from None

    @router.post('/v1/content-reports')
    async def submit(request: Request, authorization: str | None = Header(default=None)):
        async def operation(current, uid):
            body = closed_json(await request.body())
            return await run_in_threadpool(current.submit, uid, body)
        return await call(authorization, operation)

    @router.get('/v1/content-reports/receipt')
    async def receipt(request: Request, authorization: str | None = Header(default=None)):
        async def operation(current, uid):
            query = _query(request, {'reportId'})
            return await run_in_threadpool(current.receipt, uid, query.get('reportId'))
        return await call(authorization, operation)

    @router.get('/v1/content-reports')
    async def own_page(request: Request, authorization: str | None = Header(default=None)):
        async def operation(current, uid):
            after, limit = _page(request, 20)
            return await run_in_threadpool(current.page, uid, after=after, limit=limit)
        return await call(authorization, operation)

    @router.get('/v1/content-report-moderation')
    async def permission(authorization: str | None = Header(default=None)):
        async def operation(_, __):
            return {'schemaVersion': 1, 'canModerate': True}
        return await call(authorization, operation, moderation=True)

    @router.get('/v1/content-report-moderation/pending')
    async def pending(request: Request, authorization: str | None = Header(default=None)):
        async def operation(current, uid):
            after, limit = _page(request, 10)
            return await run_in_threadpool(current.page, uid, after=after, limit=limit, moderation=True)
        return await call(authorization, operation, moderation=True)

    @router.post('/v1/content-report-moderation/{case_key}/decision')
    async def decision(case_key: str, request: Request, authorization: str | None = Header(default=None)):
        async def operation(current, uid):
            body = closed_json(await request.body())
            return await run_in_threadpool(current.decide, uid, case_key, body)
        return await call(authorization, operation, moderation=True)

    return router


def _query(request, allowed):
    values = request.query_params
    if not set(values) <= allowed or any(len(values.getlist(key)) != 1 for key in values):
        raise ContentReportError('invalid_request')
    return values


def _page(request, default):
    query = _query(request, {'after', 'limit'})
    try:
        limit = int(query.get('limit', str(default)))
    except ValueError:
        raise ContentReportError('invalid_request') from None
    if str(limit) != query.get('limit', str(default)):
        raise ContentReportError('invalid_request')
    return query.get('after'), limit
