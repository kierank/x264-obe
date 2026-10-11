# BD-rate / BD-PSNR (Bjontegaard, VCEG-M33) of a test curve against an anchor.
# usage: awk -f bdrate.awk file
# input lines: <anchor|test> <rate> <quality>   (rate in any unit, quality in dB
#   or any metric where higher is better; blank and # lines ignored)
# At least 4 points per curve. Prints BD-rate (% rate change at equal quality,
# negative = test better) with the cubic least-squares fit of the original
# method and with piecewise cubic Hermite (PCHIP, as JVET/AOM CTC tools), and
# BD-quality (quality change at equal rate) with the cubic fit.

function swap_pts(c, i, j,   t) {
    t = R[c, i]; R[c, i] = R[c, j]; R[c, j] = t
    t = Q[c, i]; Q[c, i] = Q[c, j]; Q[c, j] = t
}

# sort curve c by x (x = "R" sorts by rate, else by quality)
function sort_curve(c, by,   i, j) {
    for (i = 1; i <= N[c]; i++)
        for (j = i + 1; j <= N[c]; j++)
            if ((by == "R" && R[c, j] < R[c, i]) || (by != "R" && Q[c, j] < Q[c, i]))
                swap_pts(c, i, j)
}

# least squares cubic y = a0 + a1 x + a2 x^2 + a3 x^3 through n points
function cubic_fit(n, x, y, a,   M, i, j, k, p, f, t) {
    for (i = 0; i < 4; i++) {
        for (j = 0; j < 4; j++) M[i, j] = 0
        M[i, 4] = 0
    }
    for (k = 1; k <= n; k++)
        for (i = 0; i < 4; i++) {
            for (j = 0; j < 4; j++) M[i, j] += x[k] ^ (i + j)
            M[i, 4] += y[k] * x[k] ^ i
        }
    for (i = 0; i < 4; i++) {          # Gaussian elimination, partial pivot
        p = i
        for (k = i + 1; k < 4; k++) if ((M[k, i] < 0 ? -M[k, i] : M[k, i]) > (M[p, i] < 0 ? -M[p, i] : M[p, i])) p = k
        for (j = 0; j <= 4; j++) { t = M[i, j]; M[i, j] = M[p, j]; M[p, j] = t }
        for (k = i + 1; k < 4; k++) {
            f = M[k, i] / M[i, i]
            for (j = i; j <= 4; j++) M[k, j] -= f * M[i, j]
        }
    }
    for (i = 3; i >= 0; i--) {
        t = M[i, 4]
        for (j = i + 1; j < 4; j++) t -= M[i, j] * a[j]
        a[i] = t / M[i, i]
    }
}

function cubic_int(a, lo, hi) {
    return a[0]*(hi-lo) + a[1]*(hi^2-lo^2)/2 + a[2]*(hi^3-lo^3)/3 + a[3]*(hi^4-lo^4)/4
}

# integral over [lo, hi] of the PCHIP (Fritsch-Carlson) interpolant of n sorted points
function pchip_int(n, x, y, lo, hi,   h, d, m, i, s, a, b, t, u, xa, xb, ya, yb, ma, mb, w, g, area) {
    for (i = 1; i < n; i++) { h[i] = x[i+1] - x[i]; d[i] = (y[i+1] - y[i]) / h[i] }
    if (n == 2) { m[1] = d[1]; m[2] = d[1] }
    else {
        for (i = 2; i < n; i++) {
            if (d[i-1] * d[i] <= 0) m[i] = 0
            else {
                w = 2*h[i] + h[i-1]; g = h[i] + 2*h[i-1]
                m[i] = (w + g) / (w / d[i-1] + g / d[i])
            }
        }
        # end slopes: shape-preserving three-point formula (as scipy/matlab pchip)
        m[1] = ((2*h[1] + h[2]) * d[1] - h[1] * d[2]) / (h[1] + h[2])
        if (m[1] * d[1] <= 0) m[1] = 0
        else if (d[1] * d[2] <= 0 && (m[1] < 0 ? -m[1] : m[1]) > 3*(d[1] < 0 ? -d[1] : d[1])) m[1] = 3*d[1]
        m[n] = ((2*h[n-1] + h[n-2]) * d[n-1] - h[n-1] * d[n-2]) / (h[n-1] + h[n-2])
        if (m[n] * d[n-1] <= 0) m[n] = 0
        else if (d[n-1] * d[n-2] <= 0 && (m[n] < 0 ? -m[n] : m[n]) > 3*(d[n-1] < 0 ? -d[n-1] : d[n-1])) m[n] = 3*d[n-1]
    }
    area = 0
    for (i = 1; i < n; i++) {
        a = (x[i] > lo) ? x[i] : lo
        b = (x[i+1] < hi) ? x[i+1] : hi
        if (b <= a) continue
        # Hermite cubic on [x_i, x_i+1] in t = (x - x_i)/h, integrated over [a, b]
        area += herm_int(y[i], y[i+1], m[i]*h[i], m[i+1]*h[i], (a - x[i])/h[i], (b - x[i])/h[i]) * h[i]
    }
    return area
}

# integral over t in [ta, tb] of the Hermite basis combination
function herm_int(p0, p1, m0, m1, ta, tb) {
    return hprim(p0, p1, m0, m1, tb) - hprim(p0, p1, m0, m1, ta)
}
function hprim(p0, p1, m0, m1, t) {
    # antiderivatives of h00 = 2t^3-3t^2+1, h10 = t^3-2t^2+t, h01 = -2t^3+3t^2, h11 = t^3-t^2
    return p0 * (t^4/2 - t^3 + t) + m0 * (t^4/4 - 2*t^3/3 + t^2/2) \
         + p1 * (-t^4/2 + t^3) + m1 * (t^4/4 - t^3/3)
}

function curve_xy(c, mode, x, y,   i) {
    for (i = 1; i <= N[c]; i++) {
        if (mode == "rate") { x[i] = Q[c, i]; y[i] = log(R[c, i]) / log(10) }
        else                { x[i] = log(R[c, i]) / log(10); y[i] = Q[c, i] }
    }
}

/^[ \t]*(#|$)/ { next }
{
    c = ($1 == "anchor") ? 0 : ($1 == "test") ? 1 : -1
    if (c < 0) { print "bdrate.awk: bad curve name " $1 > "/dev/stderr"; bad = 1; next }
    if ($2 <= 0) { print "bdrate.awk: rate must be > 0" > "/dev/stderr"; bad = 1; next }
    N[c]++; R[c, N[c]] = $2; Q[c, N[c]] = $3
}

END {
    if (bad || N[0] < 4 || N[1] < 4) { print "bdrate.awk: need >= 4 valid points per curve" > "/dev/stderr"; exit 1 }
    # quality must rise with rate on both curves, or the fit means nothing
    for (c = 0; c <= 1; c++) {
        sort_curve(c, "R")
        for (i = 2; i <= N[c]; i++)
            if (Q[c, i] <= Q[c, i-1]) { print "bdrate.awk: " (c ? "test" : "anchor") " quality not increasing with rate" > "/dev/stderr"; exit 1 }
    }
    # BD-rate: log rate as a function of quality
    for (c = 0; c <= 1; c++) { sort_curve(c, "Q") }
    curve_xy(0, "rate", x0, y0); curve_xy(1, "rate", x1, y1)
    lo = (x0[1] > x1[1]) ? x0[1] : x1[1]
    hi = (x0[N[0]] < x1[N[1]]) ? x0[N[0]] : x1[N[1]]
    if (hi <= lo) { print "bdrate.awk: quality ranges do not overlap" > "/dev/stderr"; exit 1 }
    cubic_fit(N[0], x0, y0, a0); cubic_fit(N[1], x1, y1, a1)
    dpoly = (cubic_int(a1, lo, hi) - cubic_int(a0, lo, hi)) / (hi - lo)
    dpchip = (pchip_int(N[1], x1, y1, lo, hi) - pchip_int(N[0], x0, y0, lo, hi)) / (hi - lo)
    # BD-quality: quality as a function of log rate
    curve_xy(0, "q", u0, v0); curve_xy(1, "q", u1, v1)
    for (c = 0; c <= 1; c++) sort_curve(c, "R")
    curve_xy(0, "q", u0, v0); curve_xy(1, "q", u1, v1)
    qlo = (u0[1] > u1[1]) ? u0[1] : u1[1]
    qhi = (u0[N[0]] < u1[N[1]]) ? u0[N[0]] : u1[N[1]]
    cubic_fit(N[0], u0, v0, b0); cubic_fit(N[1], u1, v1, b1)
    dq = (qhi > qlo) ? (cubic_int(b1, qlo, qhi) - cubic_int(b0, qlo, qhi)) / (qhi - qlo) : "n/a"
    printf "BD-rate %+.3f%% (cubic)  %+.3f%% (pchip)  BD-quality %+.4f  overlap %.3f-%.3f\n", \
        (10^dpoly - 1) * 100, (10^dpchip - 1) * 100, dq, lo, hi
}
