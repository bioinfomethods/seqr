import PropTypes from 'prop-types'
import React from 'react'
import { Icon, Message } from 'semantic-ui-react'
import styled from 'styled-components'

const StyledMessage = styled(Message)`
  width: auto !important;
`

const McriBannerMessage = React.memo(({ archieDocsUrlPath }) => (
  <StyledMessage compact icon>
    <Icon name="info" />
    <Message.Content>
      <Message.Header>Seqr Updated!</Message.Header>
      <p>
        <a
          href={archieDocsUrlPath}
          target="_blank"
          rel="noreferrer"
        >
          Click here
        </a>
        &nbsp;to see what&apos;s new.
      </p>
    </Message.Content>
  </StyledMessage>
))

McriBannerMessage.propTypes = {
  archieDocsUrlPath: PropTypes.string.isRequired,
}

export default McriBannerMessage
