# Valuation Service (ReST service)

If you like to run the valuation service locally from this repository, running `mvn spring-boot:run` or runnning `net.finmath.smartcontract.service.Appplication` starts a
ReST service providing a valuation oracle. 

## Docker: Running Valuation Service

### Run the Docker Container (starts Valuation Service)

**Important:** provide users and passwords via an `application.yml` file that resides
in `/PATH/TO/YOUR/CONFIG` (on the machine running Docker) (see Section "Config" below for the format of that file).

To run Docker Container with the image from Docker Hub execute following commands.

```
docker run -v /PATH/TO/YOUR/CONFIG:/config -p 8080:8080 finmath/finmath-smart-derivative-contract:0.1.8
```

### Config

A sample `application.yml` is
```
data:
  sdc:
    users:
      - username: user1
        password: password1
        role: USER_ONE
      - username: user2
        password: password2
        role: USER_TWO
```

### Testing the Valuation Service

Run
```
./scripts/test-margin-valuation-oracle.sh user:password
```
where `user` is a username configured in the `application.yml` (in `/PATH/TO/YOUR/CONFIG`)
and  `password` is the corresponding password configured in the `application.yml` (in `/PATH/TO/YOUR/CONFIG`) .

## Enpoints

The enpoint `https://localhost:8080/valuation/value` allows the valuation of a financial product under given market data.

The enpoint `https://localhost:8080/valuation/margin` allows the calculation of the settlement amount between two market data sets.

The market data has to be provided as a JSON.
The product data as to be provided as an XML (containing a part being an FPML of the underlying product).

See also `api.yml`.

## Value

The endpoint value calculates the value of a financial product
with given market data.

The endpoint parameters are
- product P
- market data M
- valuation time t (see note below)

**Note**: The valuation time t is currently taken from the market data set M

The result is the value
- V(P,M,t)

**Note**: The valuation time t is currently taken from the market data set M1

## Margin

The enpoint parameters are
- product P
- market data M0 (market data at previous margin call or initial valuation)
- market data M1 (market data for margin call)
- valuation time t (see note below)

The result is the value
- M(P,M0,M1,t) = V(P,M1,t) - V(P,M0,t)

**Note**: The valuation time t is currently taken from the market data set M1

## Valuation Library

The underlying valuation library is [finmath lib](https://finmath.net/finmath-lib).
