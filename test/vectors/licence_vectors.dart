// Licence token vectors (synthetic keys) from issues #25 and #34, inlined
// because browser tests cannot read files. `valid` and `reason` are the
// verifier's own outcome. It was recorded on the Dart VM with the previous
// Ed25519 implementation (ed25519_edwards 0.3.2), so the tests check that
// every compiler gives the same outcome as before. Some of these tokens are
// rejected by the consuming app for app-level rules (e.g. an unknown `tier`
// claim): the verifier does not check those claims and accepts them.

class LicenceVector {
  const LicenceVector(
      this.name, this.token, this.verifyAt, this.valid, this.reason);
  final String name;
  final String token;
  final String verifyAt;
  final bool valid;
  final String? reason;
}

const licenceVectors = <LicenceVector>[
  LicenceVector(
    'expired',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiL'
        'CJzdCI6ImFjdGl2ZSIsImVudCI6MTc2NTQ5NzYwMCwiaWF0IjoxNzY3MjI1NjAwLCJleHAiO'
        'jE3NjYxMDI0MDAsImp0aSI6InZlYy1leHBpcmVkLTAwMDEifQ.lxoe_FurWCWK9xKAyNXDj4'
        '8Gqz2U3R6c1dwFYpKspQ5vUNBsnrVB1Bhq5njZ8FG7q4ohXUzCtkL7gOcpKnEzAQ',
    '2026-01-02T00:00:00.000Z',
    false,
    'expired',
  ),
  LicenceVector(
    'next-kid',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6ImE0ZjEyMzg1'
        'ODcyOTUyODQifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJtb250aGx5I'
        'iwic3QiOiJhY3RpdmUiLCJlbnQiOjE3Njk4MTc2MDAsImlhdCI6MTc2NzIyNTYwMCwiZXhwI'
        'joxNzY4NDM1MjAwLCJqdGkiOiJ2ZWMtbmV4dC0wMDAxIn0.BuZ5cgY-eb1FwhfKUzQeUbI4J'
        'dtwd8aR9LI5pLpZSt2INU2OuzgWM6K--CyOoZVFQItd6IwssG-rCtKt4IMbCQ',
    '2026-01-02T00:00:00.000Z',
    true,
    null,
  ),
  LicenceVector(
    'next-tier-alone',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiL'
        'CJ0aWVyIjoicHJlbWl1bSIsInN0IjoiYWN0aXZlIiwiZW50IjoxNzY5ODE3NjAwLCJpYXQiO'
        'jE3NjcyMjU2MDAsImV4cCI6MTc2ODQzNTIwMCwianRpIjoidmVjLW5leHQtdGllci1iYWQtM'
        'DAwMSIsIm50aWVyIjoiZXNzZW50aWFsIn0.D0DxjbAQFCOOp8U0e-Aw4fjdKpyrn5r_bTMsw'
        'ozzJGfp5dorvmECn9yl9GciO9XRHtzuq6Cl6kmyfkrxCkMmAg',
    '2026-01-02T00:00:00.000Z',
    true,
    null,
  ),
  LicenceVector(
    'next-tier-nfrom-invalid',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiL'
        'CJ0aWVyIjoicHJlbWl1bSIsInN0IjoiYWN0aXZlIiwiZW50IjoxNzY5ODE3NjAwLCJpYXQiO'
        'jE3NjcyMjU2MDAsImV4cCI6MTc2ODQzNTIwMCwianRpIjoidmVjLW5leHQtdGllci1iYWQtM'
        'DAwMSIsIm50aWVyIjoiZXNzZW50aWFsIiwibmZyb20iOjE3Njc2NTc2MDAuNX0.awp4_Al7U'
        'ivV7lVhHrBUrtho-oaqEKuJvPMZqzMLREpD2XiGQOCy9x5xHFqdpp10QZcfeWDTyHzvQHTJ9'
        'JGHBQ',
    '2026-01-02T00:00:00.000Z',
    true,
    null,
  ),
  LicenceVector(
    'next-tier-unknown',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiL'
        'CJ0aWVyIjoicHJlbWl1bSIsInN0IjoiYWN0aXZlIiwiZW50IjoxNzY5ODE3NjAwLCJpYXQiO'
        'jE3NjcyMjU2MDAsImV4cCI6MTc2ODQzNTIwMCwianRpIjoidmVjLW5leHQtdGllci1iYWQtM'
        'DAwMSIsIm50aWVyIjoiZ29sZCIsIm5mcm9tIjoxNzY3NjU3NjAwfQ.hvGMK-VPlqYkScC579'
        'DoHjg-AZRlrVk9H2BbA8ut_HRqwu3Q6M1nNJCgfpiPB2h3E7WZznu4i-I-C5gWJ11TDg',
    '2026-01-02T00:00:00.000Z',
    true,
    null,
  ),
  LicenceVector(
    'next-tier',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiL'
        'CJ0aWVyIjoicHJlbWl1bSIsIm50aWVyIjoiZXNzZW50aWFsIiwibmZyb20iOjE3Njc2NTc2M'
        'DAsInN0IjoiYWN0aXZlIiwiZW50IjoxNzY5ODE3NjAwLCJpYXQiOjE3NjcyMjU2MDAsImV4c'
        'CI6MTc2ODQzNTIwMCwianRpIjoidmVjLW5leHQtdGllci0wMDAxIn0.FPfrSzPTUiVH3XI4G'
        'KpyDMAR8XHIKtzSOAx1wbgV22RZ5MUjDoMvu8m898BSyy81gCgjllBvBcQ34aC0jm9_Cg',
    '2026-01-02T00:00:00.000Z',
    true,
    null,
  ),
  LicenceVector(
    'tampered',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJtb250aGx5I'
        'iwic3QiOiJ0cmlhbCIsImVudCI6MTc2OTgxNzYwMCwiaWF0IjoxNzY3MjI1NjAwLCJleHAiO'
        'jE3Njg0MzUyMDAsImp0aSI6InZlYy12YWxpZC0wMDAxIn0.77pFiu5qTispPXHkuyv0ruZcw'
        '-OYy2xvagY6o6QH3NRhatEFc2tOmYpviINDjm8CmU3Ptg5oaZp6BScSqfMVBA',
    '2026-01-02T00:00:00.000Z',
    false,
    'signature_invalid',
  ),
  LicenceVector(
    'tier-essential',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiL'
        'CJ0aWVyIjoiZXNzZW50aWFsIiwic3QiOiJhY3RpdmUiLCJlbnQiOjE3Njk4MTc2MDAsImlhd'
        'CI6MTc2NzIyNTYwMCwiZXhwIjoxNzY4NDM1MjAwLCJqdGkiOiJ2ZWMtdGllci1lc3NlbnRpY'
        'WwtMDAwMSJ9.CeyBD9KSLDRmdryfKqXOQ40LEDZg6ld-Hwe2cmK7TgsaIQlmW3IYihyE4JwG'
        'JrTtw0zXwQRqzDfCQCgeKkgKDQ',
    '2026-01-02T00:00:00.000Z',
    true,
    null,
  ),
  LicenceVector(
    'tier-unknown',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiL'
        'CJzdCI6ImFjdGl2ZSIsImVudCI6MTc2OTgxNzYwMCwiaWF0IjoxNzY3MjI1NjAwLCJleHAiO'
        'jE3Njg0MzUyMDAsImp0aSI6InZlYy10aWVyLXVua25vd24tMDAwMSIsInRpZXIiOiJnb2xkI'
        'n0.IH1oUGNmvvW09IUb_opdSX5GPpYuQS1JM-8JxCqVxwp_vCtTSAVc4_-wAzoGJQn_GA_8u'
        'DEu9suNhIYSTyXMAQ',
    '2026-01-02T00:00:00.000Z',
    true,
    null,
  ),
  LicenceVector(
    'trial-premium',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJ0cmlhbCIsI'
        'nRpZXIiOiJwcmVtaXVtIiwic3QiOiJ0cmlhbCIsImVudCI6MTc2ODQzNTIwMCwiaWF0IjoxN'
        'zY3MjI1NjAwLCJleHAiOjE3Njg0MzUyMDAsImp0aSI6InZlYy10cmlhbC1wcmVtaXVtLTAwM'
        'DEifQ.YXMWIFTC-JL4Ys_wQBXCZNoQCJtZr3kZZKlboP0cXQ0jUDiH8SVGsYac8YMU3zORBm'
        'J5j7eCD1Zf14KDsaM-AA',
    '2026-01-02T00:00:00.000Z',
    true,
    null,
  ),
  LicenceVector(
    'valid',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiL'
        'CJzdCI6ImFjdGl2ZSIsImVudCI6MTc2OTgxNzYwMCwiaWF0IjoxNzY3MjI1NjAwLCJleHAiO'
        'jE3Njg0MzUyMDAsImp0aSI6InZlYy12YWxpZC0wMDAxIn0.77pFiu5qTispPXHkuyv0ruZcw'
        '-OYy2xvagY6o6QH3NRhatEFc2tOmYpviINDjm8CmU3Ptg5oaZp6BScSqfMVBA',
    '2026-01-02T00:00:00.000Z',
    true,
    null,
  ),
  LicenceVector(
    'wrong-alg',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3Y'
        'SIsInN1YiI6InVzZXItMDAwMSIsImlpZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiL'
        'CJzdCI6ImFjdGl2ZSIsImVudCI6MTc2OTgxNzYwMCwiaWF0IjoxNzY3MjI1NjAwLCJleHAiO'
        'jE3Njg0MzUyMDAsImp0aSI6InZlYy12YWxpZC0wMDAxIn0.8MctA8rV8VzUJ-qFqHZTqCT-e'
        'y_-dTyv7SbZjF68Uts',
    '2026-01-02T00:00:00.000Z',
    false,
    'alg_not_allowed',
  ),
  LicenceVector(
    'wrong-aud',
    'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlh'
        'YjhmZTRlZTEifQ.eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoib3RoZXItY'
        'XBwIiwic3ViIjoidXNlci0wMDAxIiwiaWlkIjoiaW5zdC0wMDAxIiwicGxhbiI6ImFubnVhb'
        'CIsInN0IjoiYWN0aXZlIiwiZW50IjoxNzY5ODE3NjAwLCJpYXQiOjE3NjcyMjU2MDAsImV4c'
        'CI6MTc2ODQzNTIwMCwianRpIjoidmVjLWF1ZC0wMDAxIn0.OLYwAFY0PIMxLp9lEWpMXJM5V'
        '1nf77TrPJPyLtQ6HLP9TxgTq2_YFjiTYz5uvKO5tG-8SdojAMQbSWE_DzaUCw',
    '2026-01-02T00:00:00.000Z',
    false,
    'aud_invalid',
  ),
];
