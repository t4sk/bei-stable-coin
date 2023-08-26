def rpow(x, n, b):
    z = 0
    if x == 0:
        if n == 0:
            z = b
        else:
            z = 0
    else:
        if n % 2 == 0:
            z = b
        else:
            z = x
        half = b // 2
        while n > 0:
            xx = x * x
            if xx // x != x:
                raise Exception("Revert")
            xx_round = xx + half
            if xx_round < xx:
                raise Exception("Revert")
            x = xx_round // b
            if n % 2 != 0:
                z_x = z * x
                if x != 0 and z_x // x != z:
                    raise Exception("Revert")
                z_x_round = z_x + half
                if z_x_round < z_x:
                    raise Exception("Revert")
                z = z_x_round // b
            n //= 2
    return z
