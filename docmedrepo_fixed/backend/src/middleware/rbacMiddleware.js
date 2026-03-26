'use strict';

/**
 * Middleware factory that restricts route access to specific roles.
 * Must be used AFTER authenticate middleware.
 *
 * Usage: router.get('/route', authenticate, authorise('doctor', 'admin'), handler)
 *
 * @param {...string} roles - Allowed roles
 * @returns {Function} Express middleware
 */
function authorise(...roles) {
  return (req, res, next) => {
    if (!req.role || !roles.includes(req.role)) {
      return res.status(403).json({
        error: `Access denied. Required role(s): ${roles.join(', ')}`,
      });
    }
    next();
  };
}

module.exports = { authorise };
