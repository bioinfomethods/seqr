import React from 'react'
import PropTypes from 'prop-types'
import { Grid } from 'semantic-ui-react'
import styled from 'styled-components'

const FamilyGrid = styled(({ annotation, offset, ...props }) => <Grid {...props} />)`
  margin-left: ${props => ((props.annotation || props.offset) ? '25px !important' : 'inherit')};
  margin-top: ${props => (props.annotation ? '-33px !important' : 'inherit')};
`

// These magic numbers are based on Semantic UI's 16 column grid
// https://semantic-ui.com/collections/grid.html
const getContentWidth = (useFullWidth, leftContent, rightContent) => {
  if (!useFullWidth || (leftContent && rightContent)) {
    // When both left and right content are present, the main field gets 10/16 of the width
    return 10
  }
  if (leftContent || rightContent) {
    // When sharing with left or right content, the main field gets 9/16 of the width
    return 9
  }
  // When no extra content is given, the main field takes all 16ths of the width
  return 16
}

/**
 * FamilyLayout uses a 16 column grid to display "leftContent", "fields" & "rightContent"
 * Posible layouts, given different combinations:
 * leftContent, fields, rightContent  = 3 : 10 : 3
 * leftContent, fields                = 7 : 9
 * fields                             = 16
 * fields, rightContent               = 9 : 7
 */
const FamilyLayout = React.memo((
  { leftContent, rightContent, annotation, offset, fields, fieldDisplay, useFullWidth, compact },
) => (
  <div>
    {annotation}
    <FamilyGrid annotation={annotation} offset={offset}>
      <Grid.Row>
        {(leftContent || !useFullWidth) && <Grid.Column width={rightContent ? 3 : 7}>{leftContent}</Grid.Column>}
        {compact ? (fields || []).map(
          field => <Grid.Column width={field.colWidth || 1} key={field.id}>{fieldDisplay(field)}</Grid.Column>,
        ) : (
          <Grid.Column width={getContentWidth(useFullWidth, leftContent, rightContent)}>
            {(fields || []).map(field => fieldDisplay(field))}
          </Grid.Column>
        )}
        {rightContent && <Grid.Column width={leftContent ? 3 : 7}>{rightContent}</Grid.Column>}
      </Grid.Row>
    </FamilyGrid>
  </div>
))

FamilyLayout.propTypes = {
  fieldDisplay: PropTypes.func,
  fields: PropTypes.arrayOf(PropTypes.object),
  useFullWidth: PropTypes.bool,
  compact: PropTypes.bool,
  offset: PropTypes.bool,
  annotation: PropTypes.node,
  leftContent: PropTypes.node,
  rightContent: PropTypes.node,
}

export default FamilyLayout
