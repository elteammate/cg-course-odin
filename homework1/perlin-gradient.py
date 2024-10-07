import sympy as sp

g00_x, g00_y = sp.symbols('g00_x g00_y')
g01_x, g01_y = sp.symbols('g01_x g01_y')
g10_x, g10_y = sp.symbols('g10_x g10_y')
g11_x, g11_y = sp.symbols('g11_x g11_y')

p_x, p_y = sp.symbols('p_x p_y')

g00 = sp.Matrix([g00_x, g00_y])
g01 = sp.Matrix([g01_x, g01_y])
g10 = sp.Matrix([g10_x, g10_y])
g11 = sp.Matrix([g11_x, g11_y])

def interpolate(a, b, t):
    return (b - a) * (3 - t * 2) * t * t + a

d00 = g00.dot(sp.Matrix([-p_x, -p_y]))
d01 = g01.dot(sp.Matrix([-p_x, 1 - p_y]))
d10 = g10.dot(sp.Matrix([1 - p_x, -p_y]))
d11 = g11.dot(sp.Matrix([1 - p_x, 1 - p_y]))

d00_grad = g00
d01_grad = sp.Matrix([g01_x, -g01_y])
d10_grad = sp.Matrix([-g10_x, g10_y])
d11_grad = sp.Matrix([-g11_x, -g11_y])

value = interpolate(
    interpolate(d00, d10, p_x),
    interpolate(d01, d11, p_x),
    p_y
)

sp.pprint(sp.diff(value, p_x))