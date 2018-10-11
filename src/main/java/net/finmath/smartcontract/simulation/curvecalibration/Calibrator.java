package net.finmath.smartcontract.simulation.curvecalibration;

import net.finmath.marketdata.calibration.CalibratedCurves;
import net.finmath.marketdata.model.AnalyticModel;
import net.finmath.marketdata.model.curves.*;
import net.finmath.optimizer.SolverException;
import net.finmath.time.businessdaycalendar.BusinessdayCalendarExcludingTARGETHolidays;
import net.finmath.time.businessdaycalendar.BusinessdayCalendarInterface;

import java.util.Optional;
import java.util.stream.Stream;

public class Calibrator {

    public static final String DISCOUNT_EUR_OIS = "discount-EUR-OIS";

    /**
     * @param providers
     * @param ctx The context providing reference date and accuracy.
     * @return If the calibration problem can be solved the optional wraps a {@see AnalyticModelInterface} implementation with the calibrated model; if the problem is not solvable with respect to the given accuracy, the optional will be empty.
     */
    public Optional<CalibrationResult> calibrateModel(Stream<CalibrationSpecProvider> providers, CalibrationContext ctx) throws CloneNotSupportedException {
        AnalyticModel model = new AnalyticModel(getCalibrationCurves(ctx));
        CalibratedCurves.CalibrationSpec[] specs = providers.map(c -> c.getCalibrationSpec(ctx)).toArray(CalibratedCurves.CalibrationSpec[]::new);

        try {
            return Optional.of(new CalibrationResult(new CalibratedCurves(specs, model, ctx.getAccuracy()), specs));
        } catch (SolverException e) {
            return Optional.empty();
        }
    }

    private CurveInterface[] getCalibrationCurves(CalibrationContext ctx)
    {
        return new CurveInterface[] { getOisDiscountCurve(ctx), getOisForwardCurve(ctx), get1MForwardCurve(ctx), get3MForwardCurve(ctx), get6MForwardCurve(ctx) };
    }

    private DiscountCurve getOisDiscountCurve(CalibrationContext ctx) {
        return DiscountCurve.createDiscountCurveFromDiscountFactors(DISCOUNT_EUR_OIS, ctx.getReferenceDate(), new double[]{0.0}, new double[]{1.0}, new boolean[]{false}, Curve.InterpolationMethod.LINEAR, Curve.ExtrapolationMethod.CONSTANT, Curve.InterpolationEntity.LOG_OF_VALUE);
    }

    private ForwardCurveInterface getOisForwardCurve(CalibrationContext ctx) {
        return new ForwardCurveFromDiscountCurve("forward-EUR-OIS", DISCOUNT_EUR_OIS, ctx.getReferenceDate(), "3M");
    }

    private ForwardCurveInterface get3MForwardCurve(CalibrationContext ctx) {
        return new ForwardCurve("forward-EUR-3M", ctx.getReferenceDate(), "3M", new BusinessdayCalendarExcludingTARGETHolidays(), BusinessdayCalendarInterface.DateRollConvention.FOLLOWING, Curve.InterpolationMethod.LINEAR, Curve.ExtrapolationMethod.CONSTANT, Curve.InterpolationEntity.VALUE, ForwardCurve.InterpolationEntityForward.FORWARD, DISCOUNT_EUR_OIS);
    }

    private ForwardCurveInterface get6MForwardCurve(CalibrationContext ctx) {
        return new ForwardCurve("forward-EUR-6M", ctx.getReferenceDate(), "6M", new BusinessdayCalendarExcludingTARGETHolidays(), BusinessdayCalendarInterface.DateRollConvention.FOLLOWING, Curve.InterpolationMethod.LINEAR, Curve.ExtrapolationMethod.CONSTANT, Curve.InterpolationEntity.VALUE, ForwardCurve.InterpolationEntityForward.FORWARD, DISCOUNT_EUR_OIS);
    }

    private ForwardCurveInterface get1MForwardCurve(CalibrationContext ctx) {
        return new ForwardCurve("forward-EUR-1M", ctx.getReferenceDate(), "1M", new BusinessdayCalendarExcludingTARGETHolidays(), BusinessdayCalendarInterface.DateRollConvention.FOLLOWING, Curve.InterpolationMethod.LINEAR, Curve.ExtrapolationMethod.CONSTANT, Curve.InterpolationEntity.VALUE, ForwardCurve.InterpolationEntityForward.FORWARD, DISCOUNT_EUR_OIS);
    }
}